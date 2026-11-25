import BlurHashSwift
import SwiftUI
import SwiftUIWebBrowser

/// The fixture for `Web/demo/test-browser.mjs`: four placeholders of the specification's example hashes, one behind a
/// clear view through the modifier, one malformed hash, a button that widens the tiles (a resize) and one that times the
/// decoder in WebAssembly.
let hashes = [
  "LEHV6nWB2yk8pyo0adR*.7kCMdnj",
  "LGF5]+Yk^6#M@-5c,1J5@[or[Q6.",
  "L6PZfSi_.AyE_3t7t7R**0o#DgR4",
  "LKO2:N%2Tw=w]~RBVZRi};RPxuwH",
]

/// Microseconds per call of `body`, over `repeats` calls, by the page's clock.
@MainActor func microseconds(repeats: Int, _ body: () -> Void) -> Double {
  let start = Date()
  for _ in 0..<repeats { body() }
  return Date().timeIntervalSince(start) * 1_000_000 / Double(repeats)
}

func tenths(_ value: Double) -> String {
  let scaled = Int((value * 10).rounded())
  return "\(scaled / 10).\(scaled % 10)"
}

private struct DemoRoot: View {
  @State private var wide = false
  @State private var timing = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        ForEach(0..<hashes.count, id: \.self) { index in
          BlurHashImage(hash: hashes[index])
            .frame(width: wide ? 200 : 120, height: 180)
            .accessibilityIdentifier("tile-\(index)")
        }
      }
      Color.clear
        .frame(width: 100, height: 60)
        .blurHashPlaceholder(hashes[1])
        .accessibilityIdentifier("placeholder")
      BlurHashImage(hash: "not a hash")
        .frame(width: 40, height: 40)
        .accessibilityIdentifier("invalid")
      HStack(spacing: 8) {
        Button("Resize") { wide.toggle() }
          .accessibilityIdentifier("resize")
        Button("Benchmark") {
          var sink = 0
          let decode16 = microseconds(repeats: 2000) { sink &+= Int(BlurHash.decode(hashes[0], width: 16, height: 16)!.rgba[9]) }
          let decode32 = microseconds(repeats: 1000) { sink &+= Int(BlurHash.decode(hashes[0], width: 32, height: 32)!.rgba[9]) }
          let pixels = BlurHash.decode(hashes[0], width: 32, height: 32)!
          let png = microseconds(repeats: 1000) { sink &+= pixels.pngDataURL().utf8.count }
          timing = "T|\(tenths(decode16))|\(tenths(decode32))|\(tenths(png))|\(BlurHashImageCache.count)|\(sink & 1)"
        }
        .accessibilityIdentifier("benchmark")
      }
      Text(timing)
        .accessibilityIdentifier("timing")
    }
    .padding(16)
  }
}

@main
struct BlurHashDemo: BrowserApp {
  var body: some Scene {
    WindowGroup { DemoRoot() }
  }
}
