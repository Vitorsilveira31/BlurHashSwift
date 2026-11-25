extension SRGB {
  /// The linear intensities 0...1 split into this many bins, for ``byte(_:thresholds:bins:)``.
  static let binCount = 4096

  /// `byteOfBin[k]` is the sRGB byte of the linear intensity k / binCount. A bin (1 / 4096 = 2.44e-4) is narrower than
  /// the closest two thresholds (3.03e-4, at the dark end), so it holds at most one threshold.
  static let byteOfBin: [UInt8] = {
    var table = [UInt8](repeating: 0, count: binCount + 1)
    var byte = 0
    for bin in 0...binCount {
      let value = Double(bin) / Double(binCount)
      while byte < 255 && byteThresholds[byte] <= value { byte += 1 }
      table[bin] = UInt8(byte)
    }
    return table
  }()

  /// The sRGB byte of a linear intensity, exactly as the thresholds give it: the byte of the bin's start, plus one when
  /// the one threshold the bin may hold is at or below the value. No search, so no mispredicted branches in the
  /// decoder's inner loop.
  @inline(__always)
  static func byte(_ linear: Double, thresholds: UnsafeBufferPointer<Double>, bins: UnsafeBufferPointer<UInt8>) -> UInt8 {
    guard linear > 0 else { return 0 }  // also NaN
    guard linear < 1 else { return 255 }
    let byte = bins[Int(linear * Double(binCount))]
    return byte < 255 && thresholds[Int(byte)] <= linear ? byte + 1 : byte
  }
}
