import BlurHashSwift
import SwiftUI

/// The fixture for `Android/demo/check.sh`: the specification's four example hashes as 120 by 180 point tiles (180 by 180
/// after Resize), and one behind a clear view through the modifier.

let hashes = [
    "LEHV6nWB2yk8pyo0adR*.7kCMdnj",
    "LGF5]+Yk^6#M@-5c,1J5@[or[Q6.",
    "L6PZfSi_.AyE_3t7t7R**0o#DgR4",
    "LKO2:N%2Tw=w]~RBVZRi};RPxuwH",
]

struct ContentView: View {
    @State var wide = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(0..<2, id: \.self) { index in
                    BlurHashImage(hash: hashes[index])
                        .frame(width: wide ? 180 : 120, height: 180)
                        .accessibilityIdentifier("tile-\(index)")
                }
            }
            HStack(spacing: 8) {
                ForEach(2..<4, id: \.self) { index in
                    BlurHashImage(hash: hashes[index])
                        .frame(width: wide ? 180 : 120, height: 180)
                        .accessibilityIdentifier("tile-\(index)")
                }
            }
            Text("Placeholder behind a clear view:")
            Color.clear
                .frame(width: 100, height: 60)
                .blurHashPlaceholder(hashes[1])
            Button("Resize") { wide.toggle() }
                .accessibilityIdentifier("resize")
        }
        .padding(16)
    }
}
