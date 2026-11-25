#!/usr/bin/env bun
// BlurHashSwift's BlurHashImage in a SwiftUIWeb app (Embedded Swift, WebAssembly): each placeholder is an <img> of a
// 32 by 32 PNG that the browser scales smoothly, with the pixels of the reference decoder, and a resize changes nothing
// but the element's size. Run by `bash Web/demo/run.sh --test`, which builds the demo app (Web/demo/App) first.
//
// Each scenario runs with Swift in the Worker and on the main thread (`?render-in-worker=0`), on Chromium and WebKit
// (BLURHASH_ENGINES). The Benchmark button times the decoder in WebAssembly; the times are printed, not checked.
//
// usage: bun Web/demo/test-browser.mjs <bundle directory>
import { chromium, webkit } from "@playwright/test";
import { decode } from "blurhash";
import { existsSync, statSync } from "node:fs";
import { extname, join, resolve } from "node:path";

const BUNDLE = resolve(process.argv[2] ?? "");
const ENGINES = (process.env.BLURHASH_ENGINES ?? "chromium,webkit").split(",").filter(Boolean);
const HASHES = [
  "LEHV6nWB2yk8pyo0adR*.7kCMdnj",
  "LGF5]+Yk^6#M@-5c,1J5@[or[Q6.",
  "L6PZfSi_.AyE_3t7t7R**0o#DgR4",
  "LKO2:N%2Tw=w]~RBVZRi};RPxuwH",
];
const failures = [];

function check(condition, message) {
  if (!condition) {
    failures.push(message);
    console.log(`  FAIL ${message}`);
  }
  return Boolean(condition);
}

const TYPES = { ".html": "text/html", ".js": "text/javascript", ".mjs": "text/javascript", ".css": "text/css", ".wasm": "application/wasm", ".json": "application/json" };
/** The bundle as static files; `/` and every unknown path serve index.html (the app's routes). */
function serve(directory) {
  return Bun.serve({
    port: 0,
    fetch(request) {
      const path = decodeURIComponent(new URL(request.url).pathname);
      let file = join(directory, path);
      if (!file.startsWith(directory) || !existsSync(file) || statSync(file).isDirectory()) file = join(directory, "index.html");
      return new Response(Bun.file(file), { headers: { "content-type": TYPES[extname(file)] ?? "application/octet-stream" } });
    },
  });
}

/** In the page: what the image of a tile is, as the DOM and the browser see it. */
function describe(testID) {
  const root = document.querySelector(`[data-testid="${testID}"]`);
  if (!root) return null;
  const image = root.tagName === "IMG" ? root : root.querySelector("img");
  if (!image) return { image: false };
  const box = image.getBoundingClientRect();
  return {
    image: true,
    src: image.getAttribute("src") || "",
    alt: image.getAttribute("alt"),
    complete: image.complete,
    natural: [image.naturalWidth, image.naturalHeight],
    box: [box.width, box.height],
    rendering: getComputedStyle(image).imageRendering,
  };
}

/** In the page: the RGBA bytes of a tile's image at its natural size. */
async function naturalPixels(testID) {
  const root = document.querySelector(`[data-testid="${testID}"]`);
  const image = root.tagName === "IMG" ? root : root.querySelector("img");
  await image.decode();
  const canvas = document.createElement("canvas");
  canvas.width = image.naturalWidth;
  canvas.height = image.naturalHeight;
  const context = canvas.getContext("2d");
  context.drawImage(image, 0, 0);
  return Array.from(context.getImageData(0, 0, canvas.width, canvas.height).data);
}

/** In the page: how a PNG screenshot of a 32-pixel-wide bitmap scaled across its width changes along its rows. Without
 *  filtering each bitmap pixel is repeated, so the colour changes only where one bitmap column gives way to the next
 *  (`boundaryShare` near 1); a filtered scaling changes it everywhere (`boundaryShare` near the share of such columns,
 *  32 / width). `step` is the largest difference between neighbours. */
async function scalingProfile(base64) {
  const image = new Image();
  image.src = `data:image/png;base64,${base64}`;
  await image.decode();
  const canvas = document.createElement("canvas");
  canvas.width = image.naturalWidth;
  canvas.height = image.naturalHeight;
  const context = canvas.getContext("2d");
  context.drawImage(image, 0, 0);
  const { data, width, height } = context.getImageData(0, 0, canvas.width, canvas.height);
  let step = 0;
  let changes = 0;
  const columns = [];
  // Two pixels in from each edge: the screenshot may catch a sliver of the background.
  for (let y = 2; y < height - 2; y++) {
    for (let x = 3; x < width - 2; x++) {
      let changed = false;
      for (let c = 0; c < 3; c++) {
        const at = (y * width + x) * 4 + c;
        const difference = Math.abs(data[at] - data[at - 4]);
        step = Math.max(step, difference);
        if (difference > 0) changed = true;
      }
      if (!changed) continue;
      changes++;
      columns.push(x);
    }
  }
  // Where the bitmap columns meet depends on how the engine places the samples, so the share is taken at the phase that
  // explains the most changes.
  let boundaryShare = 0;
  for (let phase = 0; phase < 1; phase += 0.125) {
    let atEdges = 0;
    for (const x of columns) {
      if (Math.floor(((x + phase) * 32) / width) !== Math.floor(((x - 1 + phase) * 32) / width)) atEdges++;
    }
    boundaryShare = Math.max(boundaryShare, changes ? atEdges / changes : 0);
  }
  return { step, boundaryShare };
}

async function scenario(browser, base, engine, worker) {
  const label = `${engine} ${worker ? "worker" : "main thread"}`;
  const context = await browser.newContext({ deviceScaleFactor: 1 });
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (error) => errors.push(String(error)));
  page.on("console", (message) => { if (message.type() === "error") errors.push(message.text()); });
  try {
    await page.goto(`${base}/?render-in-worker=${worker ? 1 : 0}`, { waitUntil: "domcontentloaded" });
    await page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 30000 });
    check((await page.evaluate(() => window.__embeddedSession.worker)) === worker, `${label}: runs in the ${worker ? "worker" : "main thread"}`);
    await page.waitForFunction(() => [...document.querySelectorAll("img")].every((image) => image.complete), null, { timeout: 10000 });

    const sources = [];
    const shares = [];
    for (let index = 0; index < HASHES.length; index++) {
      const tile = await page.evaluate(describe, `tile-${index}`);
      if (!check(tile?.image, `${label}: tile ${index} is an <img>`)) continue;
      sources.push(tile.src);
      check(tile.src.startsWith("data:image/png;base64,"), `${label}: tile ${index} shows a PNG data: URL`);
      check(tile.natural[0] === 32 && tile.natural[1] === 32, `${label}: tile ${index} is a 32 by 32 bitmap (${tile.natural})`);
      check(Math.abs(tile.box[0] - 120) < 0.5 && Math.abs(tile.box[1] - 180) < 0.5, `${label}: tile ${index} fills its 120 by 180 frame (${tile.box})`);
      check(tile.rendering === "auto", `${label}: tile ${index} is scaled with smoothing (image-rendering ${tile.rendering})`);

      // The bitmap is what the reference decoder gives, to a rounding step.
      const actual = await page.evaluate(naturalPixels, `tile-${index}`);
      const expected = decode(HASHES[index], 32, 32);
      let largest = 0;
      for (let at = 0; at < expected.length; at++) largest = Math.max(largest, Math.abs(actual[at] - expected[at]));
      check(largest <= 1, `${label}: tile ${index} has the reference decoder's pixels (largest difference ${largest})`);

      // Shown at 120 by 180 the image is filtered: its colours change between the 3.75-point columns of the bitmap, not
      // only at their edges. A twin with `image-rendering: pixelated` is the control: there they change only at the edges.
      const shot = await page.locator(`[data-testid="tile-${index}"]`).first().screenshot();
      const smooth = await page.evaluate(scalingProfile, shot.toString("base64"));
      await page.evaluate((source) => {
        const twin = document.createElement("img");
        twin.id = "pixelated-twin";
        twin.src = source;
        twin.style.cssText = "position:fixed;left:0;top:0;width:120px;height:180px;image-rendering:pixelated;z-index:9999";
        document.body.append(twin);
        return twin.decode();
      }, tile.src);
      const twinShot = await page.locator("#pixelated-twin").screenshot();
      const pixelated = await page.evaluate(scalingProfile, twinShot.toString("base64"));
      await page.evaluate(() => document.getElementById("pixelated-twin").remove());
      check(pixelated.boundaryShare > 0.9, `${label}: tile ${index}: the pixelated control changes only at column edges (${pixelated.boundaryShare.toFixed(2)})`);
      check(smooth.boundaryShare < 0.6, `${label}: tile ${index} is filtered (${smooth.boundaryShare.toFixed(2)} of its changes at column edges, largest step ${smooth.step}; pixelated ${pixelated.step})`);
      shares.push(`${smooth.boundaryShare.toFixed(2)}/${pixelated.boundaryShare.toFixed(2)}`);
    }

    const placeholder = await page.evaluate(describe, "placeholder");
    check(placeholder?.image && placeholder.src.startsWith("data:image/png;base64,"), `${label}: the modifier puts the image behind its view`);
    check(placeholder?.box && Math.abs(placeholder.box[0] - 100) < 0.5 && Math.abs(placeholder.box[1] - 60) < 0.5, `${label}: the placeholder fills its view's 100 by 60 frame (${placeholder?.box})`);
    const invalid = await page.evaluate(describe, "invalid");
    check(invalid && !invalid.image, `${label}: a malformed hash shows no image`);

    console.log(`  ${label}: share of colour changes at bitmap column edges, filtered/pixelated: ${shares.join(" ")}`);

    // A resize changes the frames, not the images: no src is written again.
    await page.evaluate(() => {
      window.__srcWrites = 0;
      new MutationObserver((records) => { window.__srcWrites += records.length; })
        .observe(document.body, { subtree: true, attributes: true, attributeFilter: ["src"] });
    });
    await page.locator('[data-testid="resize"]').first().dispatchEvent("click");
    await page.waitForFunction(() => {
      const image = document.querySelector('[data-testid="tile-0"]');
      const target = image?.tagName === "IMG" ? image : image?.querySelector("img");
      return target && Math.abs(target.getBoundingClientRect().width - 200) < 0.5;
    }, null, { timeout: 5000 }).catch(() => {});
    const resized = await page.evaluate(describe, "tile-0");
    check(Math.abs(resized.box[0] - 200) < 0.5, `${label}: the tile widens to 200 (${resized.box})`);
    check(resized.src === sources[0], `${label}: the widened tile keeps its image`);
    check((await page.evaluate(() => window.__srcWrites)) === 0, `${label}: resizing writes no src (${await page.evaluate(() => window.__srcWrites)})`);

    await page.locator('[data-testid="benchmark"]').first().dispatchEvent("click");
    await page.waitForFunction(() => (document.querySelector('[data-testid="timing"]')?.textContent || "").startsWith("T|"), null, { timeout: 30000 });
    const [, decode16, decode32, png, cached] = (await page.locator('[data-testid="timing"]').first().textContent()).split("|");
    // The placeholder shows the hash of tile 1, so it shares that tile's image.
    check(cached === "4", `${label}: four hashes decode four images, once each (${cached})`);
    console.log(`  ${label}: decode 16x16 ${decode16} µs, 32x32 ${decode32} µs, PNG data URL ${png} µs (WebAssembly)`);

    check(errors.length === 0, `${label}: no page errors (${errors.join(" | ")})`);
  } finally {
    await context.close();
  }
}

if (!existsSync(join(BUNDLE, "index.html"))) {
  console.error(`no bundle at ${BUNDLE}`);
  process.exit(2);
}
const server = serve(BUNDLE);
const base = `http://127.0.0.1:${server.port}`;
try {
  for (const engine of ENGINES) {
    const browser = await (engine === "webkit" ? webkit : chromium).launch({ executablePath: engine === "chromium" ? process.env.CHROMIUM_PATH : undefined });
    try {
      for (const worker of [true, false]) {
        console.log(`${engine}, ${worker ? "worker" : "main thread"}`);
        await scenario(browser, base, engine, worker);
      }
    } finally {
      await browser.close();
    }
  }
} finally {
  server.stop(true);
}
if (failures.length) {
  console.log(`${failures.length} failure(s)`);
  process.exit(1);
}
console.log("browser test passed");
