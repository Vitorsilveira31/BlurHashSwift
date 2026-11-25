#!/usr/bin/env bun
// Writes Tests/BlurHashCoreTests/ReferenceFixtures.swift: what the reference implementations of BlurHash produce, for
// the Swift tests to compare against.
//
//  - Decoding: Wolt's TypeScript implementation (the `blurhash` package, 2.0.5), with its own Math.cos and Math.pow.
//  - Encoding: the specification's encoder as Wolt's C and Swift implementations write it. The TypeScript encoder takes
//    the largest AC value without its absolute value (`Math.max(...val)`), unlike C (`fabsf`) and Swift (`abs`); this port
//    of the TypeScript code uses the absolute value, and the script reports when the TypeScript package disagrees.
//
// usage: (cd Scripts && bun install) && bun Scripts/generate-fixtures.mjs
import { decode, encode as typeScriptEncode } from "blurhash";
import { writeFileSync } from "node:fs";
import { join } from "node:path";

const digits = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~";
const encode83 = (n, length) => {
  let result = "";
  for (let i = 1; i <= length; i++) result += digits[Math.floor(Math.floor(n) / Math.pow(83, length - i)) % 83];
  return result;
};
const sRGBToLinear = (value) => {
  const v = value / 255;
  return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
};
const linearTosRGB = (value) => {
  const v = Math.max(0, Math.min(1, value));
  return v <= 0.0031308 ? Math.trunc(v * 12.92 * 255 + 0.5) : Math.trunc((1.055 * Math.pow(v, 1 / 2.4) - 0.055) * 255 + 0.5);
};
const signPow = (value, exponent) => (value < 0 ? -1 : 1) * Math.pow(Math.abs(value), exponent);

/** The specification's encoder (C and Swift reference semantics). */
function referenceEncode(pixels, width, height, componentsX, componentsY) {
  const factors = [];
  for (let y = 0; y < componentsY; y++) {
    for (let x = 0; x < componentsX; x++) {
      const normalisation = x === 0 && y === 0 ? 1 : 2;
      let r = 0, g = 0, b = 0;
      for (let i = 0; i < width; i++) {
        for (let j = 0; j < height; j++) {
          const basis = normalisation * Math.cos((Math.PI * x * i) / width) * Math.cos((Math.PI * y * j) / height);
          const at = 4 * i + j * width * 4;
          r += basis * sRGBToLinear(pixels[at]);
          g += basis * sRGBToLinear(pixels[at + 1]);
          b += basis * sRGBToLinear(pixels[at + 2]);
        }
      }
      const scale = 1 / (width * height);
      factors.push([r * scale, g * scale, b * scale]);
    }
  }
  const [dc, ...ac] = factors;
  let hash = encode83(componentsX - 1 + (componentsY - 1) * 9, 1);
  let maximumValue = 1;
  if (ac.length > 0) {
    const actualMaximumValue = Math.max(...ac.map((value) => Math.max(...value.map(Math.abs))));
    const quantisedMaximumValue = Math.floor(Math.max(0, Math.min(82, Math.floor(actualMaximumValue * 166 - 0.5))));
    maximumValue = (quantisedMaximumValue + 1) / 166;
    hash += encode83(quantisedMaximumValue, 1);
  } else {
    hash += encode83(0, 1);
  }
  hash += encode83((linearTosRGB(dc[0]) << 16) + (linearTosRGB(dc[1]) << 8) + linearTosRGB(dc[2]), 4);
  for (const value of ac) {
    const quantise = (v) => Math.floor(Math.max(0, Math.min(18, Math.floor(signPow(v / maximumValue, 0.5) * 9 + 9.5))));
    hash += encode83(quantise(value[0]) * 19 * 19 + quantise(value[1]) * 19 + quantise(value[2]), 2);
  }
  return hash;
}

/** A deterministic test image: smooth color fields plus a little pseudo-random noise, opaque. */
function testImage(width, height, seed) {
  const pixels = new Uint8ClampedArray(width * height * 4);
  let state = seed >>> 0;
  const random = () => ((state = (Math.imul(state, 1664525) + 1013904223) >>> 0) / 4294967296);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const at = (y * width + x) * 4;
      const u = x / width, v = y / height;
      pixels[at] = 255 * (0.5 + 0.5 * Math.sin(6 * u + seed)) * 0.8 + 50 * random();
      pixels[at + 1] = 255 * (0.5 + 0.5 * Math.cos(4 * v - seed)) * 0.8 + 50 * random();
      pixels[at + 2] = 255 * ((u + v) / 2) * 0.8 + 50 * random();
      pixels[at + 3] = 255;
    }
  }
  return pixels;
}

const hex = (bytes) => Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
const swiftString = (text) => JSON.stringify(text); // the hashes and hex need no escape beyond JSON's

// Encoding fixtures: (image, size, components) -> hash.
const encodeCases = [
  { width: 16, height: 12, seed: 1, componentsX: 4, componentsY: 3 },
  { width: 12, height: 16, seed: 2, componentsX: 1, componentsY: 1 },
  { width: 20, height: 20, seed: 3, componentsX: 9, componentsY: 9 },
  { width: 9, height: 13, seed: 4, componentsX: 5, componentsY: 7 },
];
const encodeFixtures = encodeCases.map((c) => {
  const pixels = testImage(c.width, c.height, c.seed);
  const hash = referenceEncode(pixels, c.width, c.height, c.componentsX, c.componentsY);
  const typeScript = typeScriptEncode(pixels, c.width, c.height, c.componentsX, c.componentsY);
  if (typeScript !== hash) console.log(`note: the TypeScript encoder gives ${typeScript} for ${hash} (its maximum skips abs)`);
  return { ...c, pixels: hex(pixels), hash };
});

// Decoding fixtures: published example hashes, and the encoded ones, at a non-square and a square size.
const exampleHashes = [
  "LEHV6nWB2yk8pyo0adR*.7kCMdnj",
  "LGF5]+Yk^6#M@-5c,1J5@[or[Q6.",
  "L6PZfSi_.AyE_3t7t7R**0o#DgR4",
  "LKO2:N%2Tw=w]~RBVZRi};RPxuwH",
];
const decodeHashes = [...exampleHashes, ...encodeFixtures.map((f) => f.hash)];
const decodeFixtures = [];
for (const hash of decodeHashes) {
  decodeFixtures.push({ hash, width: 12, height: 8, pixels: hex(decode(hash, 12, 8)) });
}
for (const hash of decodeHashes.slice(0, 2)) {
  decodeFixtures.push({ hash, width: 32, height: 32, pixels: hex(decode(hash, 32, 32)) });
}

const source = `// Generated by Scripts/generate-fixtures.mjs; do not edit.
// Decoded pixels come from Wolt's TypeScript implementation (blurhash 2.0.5); encoded hashes from the specification's
// encoder as Wolt's C and Swift implementations write it.

struct DecodeFixture {
  let hash: String
  let width: Int
  let height: Int
  /// RGBA bytes, two hex digits each.
  let pixels: String
}

struct EncodeFixture {
  let width: Int
  let height: Int
  let componentsX: Int
  let componentsY: Int
  /// RGBA bytes, two hex digits each.
  let pixels: String
  let hash: String
}

let exampleHashes: [String] = [
${exampleHashes.map((hash) => `  ${swiftString(hash)},`).join("\n")}
]

let decodeFixtures: [DecodeFixture] = [
${decodeFixtures.map((f) => `  DecodeFixture(hash: ${swiftString(f.hash)}, width: ${f.width}, height: ${f.height},\n                pixels: ${swiftString(f.pixels)}),`).join("\n")}
]

let encodeFixtures: [EncodeFixture] = [
${encodeFixtures.map((f) => `  EncodeFixture(width: ${f.width}, height: ${f.height}, componentsX: ${f.componentsX}, componentsY: ${f.componentsY},\n                pixels: ${swiftString(f.pixels)},\n                hash: ${swiftString(f.hash)}),`).join("\n")}
]
`;

const output = join(import.meta.dir, "..", "Tests", "BlurHashCoreTests", "ReferenceFixtures.swift");
writeFileSync(output, source);
console.log(`wrote ${output}`);
for (const f of encodeFixtures) console.log(`  ${f.componentsX} x ${f.componentsY}: ${f.hash}`);
