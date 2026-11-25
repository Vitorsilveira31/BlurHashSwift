#!/usr/bin/env bun
// Checks the BlurHash tiles in a screenshot of the Android demo app: each tile (found by its `tile-N` resource id in the
// uiautomator dump) has the expected width in points and is a filtered scaling of a 32-pixel-wide bitmap. Without
// filtering each bitmap pixel is repeated, so the colours change only where one bitmap column gives way to the next
// (a share near 1 of the changes); filtered, they change everywhere (near 32 / width in pixels).
//
// usage: bun check-screenshot.mjs <screen.png> <hierarchy.xml> <tile width in points>
import { chromium } from "../../Web/node_modules/@playwright/test/index.mjs";
import { readFileSync } from "node:fs";

const [screenshot, hierarchy, points] = [process.argv[2], process.argv[3], Number(process.argv[4])];
const xml = readFileSync(hierarchy, "utf8");
const tiles = [];
for (let index = 0; index < 4; index++) {
  const match = new RegExp(`resource-id="tile-${index}"[^>]*bounds="\\[(\\d+),(\\d+)\\]\\[(\\d+),(\\d+)\\]"`).exec(xml);
  if (!match) throw new Error(`tile-${index} is not on screen`);
  const [x0, y0, x1, y1] = match.slice(1).map(Number);
  tiles.push({ index, x: x0, y: y0, width: x1 - x0, height: y1 - y0 });
}

const browser = await chromium.launch();
const page = await browser.newPage();
const results = await page.evaluate(async ({ png, tiles }) => {
  const image = new Image();
  image.src = `data:image/png;base64,${png}`;
  await image.decode();
  const canvas = document.createElement("canvas");
  canvas.width = image.naturalWidth;
  canvas.height = image.naturalHeight;
  const context = canvas.getContext("2d");
  context.drawImage(image, 0, 0);
  return tiles.map((tile) => {
    const { data, width, height } = context.getImageData(tile.x, tile.y, tile.width, tile.height);
    let step = 0;
    const columns = [];
    for (let y = 3; y < height - 3; y++) {
      for (let x = 4; x < width - 3; x++) {
        let changed = false;
        for (let c = 0; c < 3; c++) {
          const at = (y * width + x) * 4 + c;
          const difference = Math.abs(data[at] - data[at - 4]);
          step = Math.max(step, difference);
          if (difference > 0) changed = true;
        }
        if (changed) columns.push(x);
      }
    }
    let share = 0;
    for (let phase = 0; phase < 1; phase += 0.125) {
      let atEdges = 0;
      for (const x of columns) if (Math.floor(((x + phase) * 32) / width) !== Math.floor(((x - 1 + phase) * 32) / width)) atEdges++;
      share = Math.max(share, columns.length ? atEdges / columns.length : 1);
    }
    return { ...tile, step, share };
  });
}, { png: readFileSync(screenshot).toString("base64"), tiles });
await browser.close();

let failed = false;
const density = results[0].height / 180;
for (const tile of results) {
  const widthPoints = tile.width / density;
  const ok = Math.abs(widthPoints - points) < 1.5 && tile.share < 0.4 && tile.step <= 6;
  failed ||= !ok;
  console.log(`${ok ? "ok  " : "FAIL"} tile ${tile.index}: ${widthPoints.toFixed(1)} points wide, largest step ${tile.step}, ${tile.share.toFixed(2)} of the changes at bitmap column edges`);
}
if (failed) process.exit(1);
