extension BlurHashPixels {
  /// The image as a PNG file: RGB when every pixel is opaque (as decoded images are), RGBA otherwise.
  ///
  /// The deflate blocks are stored, not compressed: a 32 by 32 placeholder is about 3 KB and is decoded faster than a
  /// compressed one. Every platform's image decoder reads it, which makes it the portable way to hand pixels to an
  /// image view that only takes encoded images (a browser `<img>`, `UIImage(data:)`).
  public func png() -> [UInt8] {
    var isOpaque = true
    var index = 3
    while index < rgba.count {
      if rgba[index] != 255 {
        isOpaque = false
        break
      }
      index += 4
    }
    let channels = isOpaque ? 3 : 4
    // Each scanline is a filter byte (0, none) followed by the pixels.
    var scanlines: [UInt8] = []
    scanlines.reserveCapacity(height * (width * channels + 1))
    var offset = 0
    for _ in 0..<height {
      scanlines.append(0)
      for _ in 0..<width {
        scanlines.append(rgba[offset])
        scanlines.append(rgba[offset + 1])
        scanlines.append(rgba[offset + 2])
        if !isOpaque { scanlines.append(rgba[offset + 3]) }
        offset += 4
      }
    }
    var file: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    var header: [UInt8] = []
    PNG.appendBigEndian(UInt32(width), to: &header)
    PNG.appendBigEndian(UInt32(height), to: &header)
    // 8 bits per channel, color type 2 (RGB) or 6 (RGBA), deflate, adaptive filtering, no interlace.
    header.append(contentsOf: [8, isOpaque ? 2 : 6, 0, 0, 0])
    PNG.appendChunk([0x49, 0x48, 0x44, 0x52], header, to: &file)
    PNG.appendChunk([0x49, 0x44, 0x41, 0x54], PNG.storedZlib(scanlines), to: &file)
    PNG.appendChunk([0x49, 0x45, 0x4E, 0x44], [], to: &file)
    return file
  }

  /// The image as a `data:image/png;base64,...` URL (see ``png()``), which a browser shows in an `<img>`.
  public func pngDataURL() -> String {
    "data:image/png;base64," + PNG.base64(png())
  }
}

enum PNG {
  /// A zlib stream of stored deflate blocks.
  static func storedZlib(_ data: [UInt8]) -> [UInt8] {
    var stream: [UInt8] = [0x78, 0x01]
    stream.reserveCapacity(data.count + data.count / 65535 * 5 + 11)
    var offset = 0
    repeat {
      let length = min(65535, data.count - offset)
      stream.append(offset + length >= data.count ? 1 : 0)
      stream.append(UInt8(length & 0xFF))
      stream.append(UInt8(length >> 8))
      stream.append(UInt8(~length & 0xFF))
      stream.append(UInt8((~length >> 8) & 0xFF))
      stream.append(contentsOf: data[offset..<offset + length])
      offset += length
    } while offset < data.count
    appendBigEndian(adler32(data), to: &stream)
    return stream
  }

  static func appendChunk(_ type: [UInt8], _ data: [UInt8], to file: inout [UInt8]) {
    appendBigEndian(UInt32(data.count), to: &file)
    file.append(contentsOf: type)
    file.append(contentsOf: data)
    appendBigEndian(crc32(data, startingWith: crc32(type, startingWith: 0)), to: &file)
  }

  static func appendBigEndian(_ value: UInt32, to bytes: inout [UInt8]) {
    bytes.append(UInt8(truncatingIfNeeded: value >> 24))
    bytes.append(UInt8(truncatingIfNeeded: value >> 16))
    bytes.append(UInt8(truncatingIfNeeded: value >> 8))
    bytes.append(UInt8(truncatingIfNeeded: value))
  }

  /// CRC-32 (ISO 3309, as PNG uses it) of `bytes`, continuing `crc`.
  static func crc32(_ bytes: [UInt8], startingWith crc: UInt32) -> UInt32 {
    var value = ~crc
    for byte in bytes {
      value = crcTable[Int((value ^ UInt32(byte)) & 0xFF)] ^ (value >> 8)
    }
    return ~value
  }

  static let crcTable: [UInt32] = {
    var table = [UInt32](repeating: 0, count: 256)
    for index in 0..<256 {
      var value = UInt32(index)
      for _ in 0..<8 { value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
      table[index] = value
    }
    return table
  }()

  /// Adler-32, the checksum that ends a zlib stream. The sums are reduced once per 5552 bytes, the most that cannot
  /// overflow 32 bits (as zlib does), rather than once per byte.
  static func adler32(_ bytes: [UInt8]) -> UInt32 {
    var a: UInt32 = 1
    var b: UInt32 = 0
    var start = 0
    while start < bytes.count {
      let end = min(start + 5552, bytes.count)
      for index in start..<end {
        a &+= UInt32(bytes[index])
        b &+= a
      }
      a %= 65521
      b %= 65521
      start = end
    }
    return b << 16 | a
  }

  /// RFC 4648 base64, with padding.
  static func base64(_ bytes: [UInt8]) -> String {
    let alphabet: [UInt8] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)
    var output: [UInt8] = []
    output.reserveCapacity((bytes.count + 2) / 3 * 4)
    var index = 0
    while index + 2 < bytes.count {
      let value = Int(bytes[index]) << 16 | Int(bytes[index + 1]) << 8 | Int(bytes[index + 2])
      output.append(alphabet[value >> 18])
      output.append(alphabet[(value >> 12) & 63])
      output.append(alphabet[(value >> 6) & 63])
      output.append(alphabet[value & 63])
      index += 3
    }
    let remaining = bytes.count - index
    if remaining > 0 {
      let value = Int(bytes[index]) << 16 | (remaining == 2 ? Int(bytes[index + 1]) << 8 : 0)
      output.append(alphabet[value >> 18])
      output.append(alphabet[(value >> 12) & 63])
      output.append(remaining == 2 ? alphabet[(value >> 6) & 63] : UInt8(ascii: "="))
      output.append(UInt8(ascii: "="))
    }
    return String(decoding: output, as: UTF8.self)
  }
}
