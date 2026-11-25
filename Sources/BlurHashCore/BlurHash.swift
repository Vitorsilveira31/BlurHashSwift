/// An image decoded from a BlurHash, or the image to encode into one: rows of RGBA pixels, 8 bits per channel, top
/// row first. Decoded images are opaque (alpha 255).
public struct BlurHashPixels: Hashable, Sendable {
  public let width: Int
  public let height: Int
  /// `width * height * 4` bytes: red, green, blue and alpha of each pixel, row by row.
  public let rgba: [UInt8]

  /// Pixels from `width * height * 4` RGBA bytes.
  public init(width: Int, height: Int, rgba: [UInt8]) {
    precondition(width > 0 && height > 0 && rgba.count == width * height * 4, "rgba must hold width * height * 4 bytes")
    self.width = width
    self.height = height
    self.rgba = rgba
  }
}

/// A color in sRGB, 0...255 per channel.
public struct BlurHashColor: Hashable, Sendable {
  public let red: UInt8
  public let green: UInt8
  public let blue: UInt8

  public init(red: UInt8, green: UInt8, blue: UInt8) {
    self.red = red
    self.green = green
    self.blue = blue
  }
}

/// BlurHash (https://blurha.sh), written in plain Swift from the specification: no Foundation, no math library, no UI,
/// so the same code runs on Apple platforms, Linux, Android and Embedded Swift in the browser.
public enum BlurHash {
  /// True when `hash` has a valid size flag, length and alphabet.
  public static func isValid(_ hash: String) -> Bool {
    parse(hash) != nil
  }

  /// The number of horizontal and vertical components of `hash` (1...9 each), or nil when it is malformed.
  public static func components(_ hash: String) -> (x: Int, y: Int)? {
    guard let parsed = parse(hash) else { return nil }
    return (parsed.componentsX, parsed.componentsY)
  }

  /// The average color of the image, which a hash stores as is, or nil when `hash` is malformed.
  public static func averageColor(_ hash: String) -> BlurHashColor? {
    guard let parsed = parse(hash) else { return nil }
    return BlurHashColor(
      red: UInt8(truncatingIfNeeded: parsed.dc >> 16), green: UInt8(truncatingIfNeeded: parsed.dc >> 8),
      blue: UInt8(truncatingIfNeeded: parsed.dc))
  }

  /// Decodes `hash` into a `width` by `height` image, or nil when the hash is malformed or a size is not positive.
  ///
  /// The image is a smooth function of the position in the frame, so a small one (16 to 32 pixels a side) scaled up
  /// with bilinear filtering looks like a large one; the aspect ratio does not matter either, as the image stretches
  /// to its frame. `punch` scales the contrast of the details: above 1 stronger, below 1 softer.
  public static func decode(_ hash: String, width: Int, height: Int, punch: Double = 1) -> BlurHashPixels? {
    guard width > 0, height > 0, let parsed = parse(hash) else { return nil }
    let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
    guard !overflow, pixelCount <= Int.max / 4 else { return nil }
    let componentsX = parsed.componentsX
    let componentsY = parsed.componentsY

    // The linear color of each component, three doubles each, in the order of the hash (x fastest).
    var colors = [Double](repeating: 0, count: componentsX * componentsY * 3)
    colors[0] = SRGB.linearFromByte[(parsed.dc >> 16) & 255]
    colors[1] = SRGB.linearFromByte[(parsed.dc >> 8) & 255]
    colors[2] = SRGB.linearFromByte[parsed.dc & 255]
    let maximum = Double(parsed.quantisedMaximum + 1) / 166 * (punch.isFinite ? max(0, punch) : 1)
    var component = 1
    while component < componentsX * componentsY {
      let value = parsed.ac[component - 1]
      colors[component * 3] = signedSquare(Double(value / (19 * 19) - 9) / 9) * maximum
      colors[component * 3 + 1] = signedSquare(Double((value / 19) % 19 - 9) / 9) * maximum
      colors[component * 3 + 2] = signedSquare(Double(value % 19 - 9) / 9) * maximum
      component += 1
    }

    let cosinesX = basis(count: width, components: componentsX)
    let cosinesY = basis(count: height, components: componentsY)
    var rgba = [UInt8](repeating: 255, count: pixelCount * 4)
    var row = [Double](repeating: 0, count: componentsX * 3)
    rgba.withUnsafeMutableBufferPointer { output in
      row.withUnsafeMutableBufferPointer { row in
        colors.withUnsafeBufferPointer { colors in
          cosinesX.withUnsafeBufferPointer { cosinesX in
            cosinesY.withUnsafeBufferPointer { cosinesY in
              SRGB.byteThresholds.withUnsafeBufferPointer { thresholds in
                SRGB.byteOfBin.withUnsafeBufferPointer { bins in
                  synthesize(
                    into: output, row: row, colors: colors, cosinesX: cosinesX, cosinesY: cosinesY,
                    thresholds: thresholds, bins: bins, width: width, height: height, componentsX: componentsX,
                    componentsY: componentsY)
                }
              }
            }
          }
        }
      }
    }
    return BlurHashPixels(width: width, height: height, rgba: rgba)
  }

  /// The pixels of the components `colors`, through the basis tables. The basis is separable: each row first sums the
  /// vertical components (one color per horizontal component, into `row`), and each pixel then sums those, so a pixel
  /// costs componentsX steps instead of componentsX * componentsY.
  @inline(__always)
  private static func synthesize(
    into output: UnsafeMutableBufferPointer<UInt8>, row: UnsafeMutableBufferPointer<Double>,
    colors: UnsafeBufferPointer<Double>, cosinesX: UnsafeBufferPointer<Double>, cosinesY: UnsafeBufferPointer<Double>,
    thresholds: UnsafeBufferPointer<Double>, bins: UnsafeBufferPointer<UInt8>, width: Int, height: Int,
    componentsX: Int, componentsY: Int
  ) {
    var offset = 0
    for y in 0..<height {
      for i in 0..<componentsX {
        var red = 0.0
        var green = 0.0
        var blue = 0.0
        for j in 0..<componentsY {
          let basis = cosinesY[y * componentsY + j]
          let at = (j * componentsX + i) * 3
          red += colors[at] * basis
          green += colors[at + 1] * basis
          blue += colors[at + 2] * basis
        }
        row[i * 3] = red
        row[i * 3 + 1] = green
        row[i * 3 + 2] = blue
      }
      for x in 0..<width {
        var red = 0.0
        var green = 0.0
        var blue = 0.0
        for i in 0..<componentsX {
          let basis = cosinesX[x * componentsX + i]
          red += row[i * 3] * basis
          green += row[i * 3 + 1] * basis
          blue += row[i * 3 + 2] * basis
        }
        output[offset] = SRGB.byte(red, thresholds: thresholds, bins: bins)
        output[offset + 1] = SRGB.byte(green, thresholds: thresholds, bins: bins)
        output[offset + 2] = SRGB.byte(blue, thresholds: thresholds, bins: bins)
        offset += 4
      }
    }
  }

  /// Encodes an image into a hash of `componentsX` by `componentsY` components (1...9 each; 4 by 3 is usual), or nil
  /// when a component count is out of range. Alpha is ignored.
  ///
  /// The cost grows with the number of pixels, so encode a thumbnail (100 pixels a side is plenty) rather than the
  /// full image: the hash keeps only the coarsest frequencies anyway.
  public static func encode(_ pixels: BlurHashPixels, componentsX: Int = 4, componentsY: Int = 3) -> String? {
    guard (1...9).contains(componentsX), (1...9).contains(componentsY) else { return nil }
    let width = pixels.width
    let height = pixels.height
    let cosinesX = basis(count: width, components: componentsX)
    let cosinesY = basis(count: height, components: componentsY)

    // factors[(j * componentsX + i) * 3 + channel]: the projection of the image on each basis function.
    var factors = [Double](repeating: 0, count: componentsX * componentsY * 3)
    var row = [Double](repeating: 0, count: componentsX * 3)
    factors.withUnsafeMutableBufferPointer { factors in
      row.withUnsafeMutableBufferPointer { row in
        pixels.rgba.withUnsafeBufferPointer { rgba in
          cosinesX.withUnsafeBufferPointer { cosinesX in
            cosinesY.withUnsafeBufferPointer { cosinesY in
              SRGB.linearFromByte.withUnsafeBufferPointer { linear in
                project(
                  rgba, into: factors, row: row, cosinesX: cosinesX, cosinesY: cosinesY, linear: linear, width: width,
                  height: height, componentsX: componentsX, componentsY: componentsY)
              }
            }
          }
        }
      }
    }
    // The DC component is the mean; the others are normalised by 2 (the basis functions' mean square is 1/2).
    let scale = 1 / Double(width * height)
    for index in 0..<factors.count { factors[index] *= index < 3 ? scale : 2 * scale }

    var hash: [UInt8] = []
    hash.reserveCapacity(4 + 2 * componentsX * componentsY)
    Base83.encode((componentsX - 1) + (componentsY - 1) * 9, length: 1, into: &hash)
    var maximum = 1.0
    if factors.count > 3 {
      var actualMaximum = 0.0
      for index in 3..<factors.count { actualMaximum = max(actualMaximum, abs(factors[index])) }
      let quantisedMaximum = Int(max(0, min(82, (actualMaximum * 166 - 0.5).rounded(.down))))
      maximum = Double(quantisedMaximum + 1) / 166
      Base83.encode(quantisedMaximum, length: 1, into: &hash)
    } else {
      Base83.encode(0, length: 1, into: &hash)
    }
    let dc = Int(sRGBByte(factors[0])) << 16 | Int(sRGBByte(factors[1])) << 8 | Int(sRGBByte(factors[2]))
    Base83.encode(dc, length: 4, into: &hash)
    var at = 3
    while at < factors.count {
      let red = quantiseAC(factors[at], maximum)
      let green = quantiseAC(factors[at + 1], maximum)
      let blue = quantiseAC(factors[at + 2], maximum)
      Base83.encode(red * 19 * 19 + green * 19 + blue, length: 2, into: &hash)
      at += 3
    }
    return String(decoding: hash, as: UTF8.self)
  }

  /// Encodes `width * height` RGBA pixels (`rgba.count == width * height * 4`), or nil when the sizes do not match or
  /// a component count is out of range. See ``encode(_:componentsX:componentsY:)``.
  public static func encode(
    rgba: [UInt8], width: Int, height: Int, componentsX: Int = 4, componentsY: Int = 3
  ) -> String? {
    guard width > 0, height > 0 else { return nil }
    let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
    guard !overflow, pixelCount <= Int.max / 4, rgba.count == pixelCount * 4 else { return nil }
    return encode(BlurHashPixels(width: width, height: height, rgba: rgba), componentsX: componentsX,
                  componentsY: componentsY)
  }

  /// The sums of the image's linear colors times each basis function, into `factors`. Separable like ``synthesize``:
  /// each row is first projected on the horizontal components (into `row`), then added to the vertical ones.
  @inline(__always)
  private static func project(
    _ rgba: UnsafeBufferPointer<UInt8>, into factors: UnsafeMutableBufferPointer<Double>,
    row: UnsafeMutableBufferPointer<Double>, cosinesX: UnsafeBufferPointer<Double>,
    cosinesY: UnsafeBufferPointer<Double>, linear: UnsafeBufferPointer<Double>, width: Int, height: Int,
    componentsX: Int, componentsY: Int
  ) {
    var offset = 0
    for y in 0..<height {
      for index in 0..<row.count { row[index] = 0 }
      for x in 0..<width {
        let red = linear[Int(rgba[offset])]
        let green = linear[Int(rgba[offset + 1])]
        let blue = linear[Int(rgba[offset + 2])]
        for i in 0..<componentsX {
          let basis = cosinesX[x * componentsX + i]
          row[i * 3] += red * basis
          row[i * 3 + 1] += green * basis
          row[i * 3 + 2] += blue * basis
        }
        offset += 4
      }
      for j in 0..<componentsY {
        let basis = cosinesY[y * componentsY + j]
        for i in 0..<componentsX {
          let at = (j * componentsX + i) * 3
          factors[at] += row[i * 3] * basis
          factors[at + 1] += row[i * 3 + 1] * basis
          factors[at + 2] += row[i * 3 + 2] * basis
        }
      }
    }
  }

  // MARK: - Parsing

  struct Parsed {
    let componentsX: Int
    let componentsY: Int
    let quantisedMaximum: Int
    let dc: Int
    let ac: [Int]
  }

  static func parse(_ hash: String) -> Parsed? {
    let bytes = Array(hash.utf8)
    return bytes.withUnsafeBufferPointer { bytes -> Parsed? in
      guard bytes.count >= 6, let sizeFlag = Base83.decode(bytes, from: 0, length: 1) else { return nil }
      let componentsX = sizeFlag % 9 + 1
      let componentsY = sizeFlag / 9 + 1
      guard bytes.count == 4 + 2 * componentsX * componentsY,
            let quantisedMaximum = Base83.decode(bytes, from: 1, length: 1),
            let dc = Base83.decode(bytes, from: 2, length: 4)
      else { return nil }
      var ac: [Int] = []
      ac.reserveCapacity(componentsX * componentsY - 1)
      var component = 1
      while component < componentsX * componentsY {
        guard let value = Base83.decode(bytes, from: 4 + component * 2, length: 2) else { return nil }
        ac.append(value)
        component += 1
      }
      return Parsed(componentsX: componentsX, componentsY: componentsY, quantisedMaximum: quantisedMaximum, dc: dc,
                    ac: ac)
    }
  }

  // MARK: - Math

  /// `cosines[p * components + c]` = cos(pi * p * c / count) for every position p and component c.
  static func basis(count: Int, components: Int) -> [Double] {
    var cosines = [Double](repeating: 0, count: count * components)
    for position in 0..<count {
      for component in 0..<components {
        cosines[position * components + component] = cosPi(position * component, over: count)
      }
    }
    return cosines
  }

  /// The sRGB byte of a linear intensity: linearTosRGB of the specification, through the tables of `SRGB`.
  static func sRGBByte(_ linear: Double) -> UInt8 {
    SRGB.byteThresholds.withUnsafeBufferPointer { thresholds in
      SRGB.byteOfBin.withUnsafeBufferPointer { bins in SRGB.byte(linear, thresholds: thresholds, bins: bins) }
    }
  }

  @inline(__always)
  private static func signedSquare(_ value: Double) -> Double {
    value < 0 ? -(value * value) : value * value
  }

  @inline(__always)
  private static func quantiseAC(_ value: Double, _ maximum: Double) -> Int {
    let ratio = value / maximum
    let root = ratio < 0 ? -(-ratio).squareRoot() : ratio.squareRoot()
    return Int(max(0, min(18, (root * 9 + 9.5).rounded(.down))))
  }
}
