# BlurHashSwift

[BlurHash](https://blurha.sh) placeholders for SwiftUI on Apple platforms, on Android through
[Skip](https://skip.dev), and in the browser through [SwiftUIWeb](https://github.com/Vitorsilveira31/SwiftUIWeb), with
one API:

```swift
import BlurHashSwift

AsyncImage(url: poster.url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
  .frame(width: 120, height: 180)
  .blurHashPlaceholder(poster.blurHash)
  .clipped()
```

The codec is plain Swift written from the BlurHash specification, with no Foundation and no math library, so the same
code decodes on iOS, macOS, Linux, Android and in Embedded Swift for WebAssembly.

## Why it is fast

A BlurHash describes a few cosine waves, so the image it decodes to is smooth everywhere. A common way to show one is to
decode 16 by 16 pixels, paint them as 256 rectangles in a `Canvas` and blur the result. That redraws the canvas and runs
the blur on every size change, and keeps doing so for as long as the placeholder stays mounted under the loaded image.

BlurHashSwift decodes the hash once into a 32 by 32 bitmap, keeps it in a cache keyed by hash and size, and shows it as
an ordinary image that the platform scales with bilinear filtering. The filtering is what makes the gradient smooth, so
there is no blur and nothing to redraw: a resize changes the frame of a texture the compositor already has.

| Platform | What the view shows | Scaling |
|---|---|---|
| Apple (SwiftUI) | a `CGImage` of the pixels in `Image(decorative:scale:)` | `.resizable().interpolation(.medium)`, by Core Animation |
| Android (Skip Fuse) | a `UIImage` of the pixels as a PNG, which Skip decodes once into an `android.graphics.Bitmap` | Compose's `BitmapPainter`, bilinear (`FilterQuality.Low`) |
| Browser (SwiftUIWeb) | an `<img>` whose source is the PNG as a `data:` URL | the browser's compositor (`image-rendering: auto`) |

A stretched square bitmap is the same picture as one decoded at the frame's aspect ratio: the basis functions take the
position as a fraction of the frame. So one 32 by 32 image serves every frame size.

## Installation

Swift Package Manager:

```swift
.package(url: "https://github.com/Vitorsilveira31/BlurHashSwift.git", from: "0.1.0")
```

and the product in your target:

```swift
.product(name: "BlurHashSwift", package: "BlurHashSwift")  // the view and the modifier (re-exports BlurHashCore)
.product(name: "BlurHashCore", package: "BlurHashSwift")   // only the codec: decode, encode, the cache
```

The package picks its UI layer from the build:

- **Apple platforms** (iOS 16, macOS 13, tvOS 16, watchOS 9, visionOS 1): Apple's SwiftUI. Nothing else is fetched.
- **Android with Skip Fuse**: Skip's Android build sets `TARGET_OS_ANDROID`, and the package then takes `SwiftUI` from
  [skip-fuse-ui](https://github.com/skiptools/skip-fuse-ui) (1.0 or later). Add BlurHashSwift to the module that shows
  it, as any Swift dependency. The library is built without Skip's plugin, so it needs no `Skip/skip.yml` and apps that
  only target Apple platforms fetch nothing of Skip's; on Android `BlurHashImage` bridges itself to Compose through
  skip-fuse-ui's `SkipUIBridging`, as the plugin would for a view without state.
- **SwiftUIWeb**: the browser build sets `SWIFTUIWEB_EMBEDDED`, and the package then takes `SwiftUI` from SwiftUIWeb
  (0.1.40 or later). For a native build against SwiftUIWeb (tests of a web app on the Mac or Linux), set
  `BLURHASHSWIFT_SWIFTUIWEB=1`.

## Usage

### The view

```swift
BlurHashImage(hash: "LEHV6nWB2yk8pyo0adR*.7kCMdnj")
  .frame(width: 120, height: 180)
```

`BlurHashImage` fills its frame. A malformed hash shows nothing (a clear color that still takes the frame).

```swift
BlurHashImage(hash: hash, resolution: 16, punch: 1.2)
```

- `resolution`: the side of the decoded bitmap, 32 by default. 16 is enough for small thumbnails and uses a quarter of
  the memory.
- `punch`: the contrast of the details; above 1 stronger, below 1 softer.

### The modifier

```swift
content.blurHashPlaceholder(hash)   // hash: String?, nothing when nil
```

draws the placeholder behind `content`, filling its frame. Keeping it mounted under the loaded image costs nothing after
the first frame.

### The cache

Decoded images are kept by hash, resolution and punch, so a hash is decoded once however many views show it.

```swift
BlurHashImageCache.countLimit = 512   // 256 by default; a 32 by 32 image is 4 KB
BlurHashImageCache.removeAll()
```

### The codec

```swift
import BlurHashCore

let pixels = BlurHash.decode(hash, width: 32, height: 32)       // BlurHashPixels? (RGBA, row by row)
let average = BlurHash.averageColor(hash)                       // BlurHashColor?
let isValid = BlurHash.isValid(hash)
let components = BlurHash.components(hash)                      // (x: 4, y: 3)?

let hash = BlurHash.encode(thumbnail, componentsX: 4, componentsY: 3)
let hash = BlurHash.encode(rgba: bytes, width: 100, height: 75)

let png: [UInt8] = pixels.png()                                 // stored (uncompressed) PNG
let url: String = pixels.pngDataURL()                           // data:image/png;base64,...

let cache = BlurHashCache<MyImage>(countLimit: 128)             // the same cache, for your own image type
```

`encode` costs time in proportion to the number of pixels; encode a thumbnail (100 pixels a side is plenty), since the
hash keeps only the coarsest frequencies.

## Performance

Median time per call of `swift run -c release BlurHashBenchmark` (and its equivalent in each runtime). The machine was
shared with other builds while measuring, so read these as orders of magnitude.

| | Apple M5 Pro, macOS (native) | Android emulator, arm64 (native, Skip's Swift SDK 6.4.2) | Chromium, WebAssembly (Embedded) | WebKit, WebAssembly (Embedded) |
|---|---|---|---|---|
| decode 4×3 components, 16×16 | 2.2 µs | 4.6–5.0 µs | 4–8.5 µs | 3.5–9 µs |
| decode 4×3 components, 32×32 | 7 µs | 17–22 µs | 11–20 µs | 9–23 µs |
| decode 9×9 components, 32×32 | 14 µs | 43 µs | | |
| PNG data URL of a 32×32 image | 14 µs | 42 µs | 28–45 µs | 22–49 µs |
| encode 100×100, 4×3 components | 32 µs | 55 µs | | |

The browser figures come from the demo app's Benchmark button (Web/demo), timed with the page's millisecond clock over
1000 calls.
On GitHub's hosted CI runners the 32×32 decode (4×3 components) takes 13 µs on macOS and 17 µs on Linux x86_64.

A decode happens once per hash, on first display. After that a view costs one dictionary lookup per body evaluation, and
a resize costs nothing in the library: the browser test checks that widening the tiles writes no `src`, and the Apple
test renders the same cached image at any size.

## How it is tested

- **Codec** (`Tests/BlurHashCoreTests`, Swift Testing): decoded pixels against Wolt's TypeScript implementation for four
  published hashes and four encoded ones, at 12×8 and 32×32 (equal to the byte in more than 99.9 % of the channels, never
  more than 1 apart); encoded hashes against the specification's encoder for 1×1, 4×3, 5×7 and 9×9 components (exactly);
  the replacements for `cos` and `pow` against the platform's math library; the PNG (chunk checksums, RFC 4648 base64,
  CRC-32 and Adler-32 test vectors, and on Apple platforms ImageIO reading the same pixels back); the cache (once per key,
  least recently used eviction). The fixtures are generated by `Scripts/generate-fixtures.mjs`.
- **Apple view** (`Tests/BlurHashSwiftTests`): `ImageRenderer` renders `BlurHashImage` at 160×240 and the test reads the
  pixels: close to the hash decoded at full size, no steps between neighbours (a nearest-neighbour control shows them),
  the modifier draws behind its view, a malformed hash draws nothing, one decode per hash and resolution.
- **Browser** (`Web/demo`, Playwright): a SwiftUIWeb app built with the Embedded WebAssembly toolchain, in Chromium and
  WebKit, with Swift in a worker and on the main thread. Each tile is an `<img>` of a 32×32 PNG data URL with the
  reference decoder's pixels, fills its frame, is filtered when scaled (its colors change between the bitmap's columns,
  where an `image-rendering: pixelated` control changes only at their edges), and keeps its image when resized.
- **Android** (`Android/demo`): the codec tests run natively on an emulator (`skip android test`). `check.sh` builds a
  Skip Fuse app that shows the four example hashes, installs it on the running emulator or device, and reads the
  screenshot: each tile has its frame's width before and after a resize, and is filtered when scaled (the same column
  measure as the browser test). Skip 1.9.20's instrumented runner (`skip android test --apk`) crashes in its own harness
  before running a test, so the view is checked through the app rather than a unit test.
- **CI**: the tests on macOS and Linux, and `BlurHashCore` built with the Embedded Swift SDK for WebAssembly.

Run them:

```sh
swift test                                                  # codec and Apple view
swift run -c release BlurHashBenchmark                      # timings
skip android test                                           # codec on a running Android emulator or device
bash Android/demo/check.sh                                  # the view in a Skip Fuse app on that emulator or device
SWIFTUIWEB_ROOT=../SwiftUIWeb bash Web/demo/run.sh --test   # browser test (needs a SwiftUIWeb checkout and bun)
```

## Credits and license

BlurHash was designed by Wolt; its specification and reference implementations are at
[woltapp/blurhash](https://github.com/woltapp/blurhash) under the MIT License. This package is written from the
specification and copies no code from them (see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)).

BlurHashSwift is released under the MIT License (see [LICENSE](LICENSE)).
