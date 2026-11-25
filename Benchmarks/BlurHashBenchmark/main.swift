// Decode and encode times of BlurHashCore: `swift run -c release BlurHashBenchmark`.
import BlurHashCore

let hashes = [
  "LEHV6nWB2yk8pyo0adR*.7kCMdnj",  // 4 x 3 components, the specification's example
  "LGF5]+Yk^6#M@-5c,1J5@[or[Q6.",  // 4 x 3
  // 9 x 9, the most a hash has
  "|wHCxx7C$O-9OA$%WnxZWUqKWFjZjHa#jGfPjGj[eFf8j?azj?fRa}f7bHthW.jaj@bFjbjZbajsa3jaa}azaybHbHayjtt6W;j@j@ayfRjsj?bGaLjuf7a#fRayjba#a#oyW.j?j?fjjubGjbjsaLjabHa#fPf6f7bHjs",
]

/// The median time of `body` in microseconds, over `runs` runs of `repeats` calls each.
func median(runs: Int = 31, repeats: Int, _ body: () -> Void) -> Double {
  var times: [Double] = []
  let clock = ContinuousClock()
  for _ in 0..<runs {
    let elapsed = clock.measure {
      for _ in 0..<repeats { body() }
    }
    let (seconds, attoseconds) = elapsed.components
    times.append((Double(seconds) * 1e6 + Double(attoseconds) / 1e12) / Double(repeats))
  }
  times.sort()
  return times[times.count / 2]
}

func format(_ microseconds: Double) -> String {
  let tenths = Int((microseconds * 10).rounded())
  return "\(tenths / 10).\(tenths % 10) µs"
}

func run() {
  var sink = 0
  print("decode (median per call)")
  for hash in hashes {
    let (x, y) = BlurHash.components(hash)!
    for side in [16, 32] {
      let time = median(repeats: 200) {
        sink &+= Int(BlurHash.decode(hash, width: side, height: side)!.rgba[side * 2])
      }
      print("  \(x) x \(y) components, \(side) x \(side) pixels: \(format(time))")
    }
  }

  print("PNG data URL of a decoded 32 x 32 image")
  let decoded = BlurHash.decode(hashes[0], width: 32, height: 32)!
  let pngTime = median(repeats: 200) { sink &+= decoded.pngDataURL().utf8.count }
  print("  \(format(pngTime)), \(decoded.pngDataURL().utf8.count) characters")

  print("encode (median per call), 4 x 3 components")
  for side in [32, 100] {
    let image = BlurHash.decode(hashes[1], width: side, height: side)!
    let time = median(runs: 15, repeats: 20) { sink &+= BlurHash.encode(image)!.utf8.count }
    print("  \(side) x \(side) pixels: \(format(time))")
  }
  if sink == 42 { print("") }
}

run()
