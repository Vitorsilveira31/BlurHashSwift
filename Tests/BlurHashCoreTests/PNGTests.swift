@testable import BlurHashCore
import Testing

#if canImport(ImageIO)
import ImageIO
#endif

@Suite struct PNGTests {
  @Test func checksumsMatchTheirStandardVectors() {
    #expect(PNG.crc32(Array("123456789".utf8), startingWith: 0) == 0xCBF4_3926)
    #expect(PNG.adler32(Array("Wikipedia".utf8)) == 0x11E6_0398)
  }

  @Test(arguments: [("", ""), ("f", "Zg=="), ("fo", "Zm8="), ("foo", "Zm9v"), ("foob", "Zm9vYg=="),
                    ("fooba", "Zm9vYmE="), ("foobar", "Zm9vYmFy")])
  func base64MatchesRFC4648(_ text: String, _ encoded: String) {
    #expect(PNG.base64(Array(text.utf8)) == encoded)
  }

  @Test func opaquePixelsMakeAnRGBFile() throws {
    let pixels = try #require(BlurHash.decode(exampleHashes[0], width: 32, height: 32))
    let file = pixels.png()
    #expect(Array(file[0..<8]) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    // IHDR: length 13, then the width, height, depth 8, color type 2.
    #expect(Array(file[8..<16]) == [0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52])
    #expect(Array(file[16..<26]) == [0, 0, 0, 32, 0, 0, 0, 32, 8, 2])
    // Signature, IHDR, IDAT (zlib header, one stored block, the scanlines, Adler-32) and IEND.
    let scanlines = 32 * (32 * 3 + 1)
    #expect(file.count == 8 + 25 + (12 + 2 + 5 + scanlines + 4) + 12)
    #expect(pixels.pngDataURL().hasPrefix("data:image/png;base64,iVBORw0KGgo"))
  }

  @Test func translucentPixelsKeepTheirAlpha() {
    let pixels = BlurHashPixels(width: 1, height: 1, rgba: [10, 20, 30, 40])
    let file = pixels.png()
    #expect(file[25] == 6)
  }

  @Test func everyChunkChecksumIsValid() throws {
    let file = try #require(BlurHash.decode(exampleHashes[1], width: 20, height: 9)).png()
    var offset = 8
    var types: [String] = []
    while offset < file.count {
      let length = Int(file[offset]) << 24 | Int(file[offset + 1]) << 16 | Int(file[offset + 2]) << 8 | Int(file[offset + 3])
      let body = Array(file[offset + 4..<offset + 8 + length])
      let stored = UInt32(file[offset + 8 + length]) << 24 | UInt32(file[offset + 9 + length]) << 16
        | UInt32(file[offset + 10 + length]) << 8 | UInt32(file[offset + 11 + length])
      #expect(PNG.crc32(body, startingWith: 0) == stored)
      types.append(String(decoding: body[0..<4], as: UTF8.self))
      offset += 12 + length
    }
    #expect(types == ["IHDR", "IDAT", "IEND"])
  }

  @Test func storedBlocksSplitAt65535Bytes() {
    let data = [UInt8](repeating: 7, count: 65535 * 2 + 10)
    let stream = PNG.storedZlib(data)
    #expect(stream.count == 2 + 3 * 5 + data.count + 4)
    #expect(stream[2] == 0 && stream[2 + 5 + 65535] == 0 && stream[2 + 2 * (5 + 65535)] == 1)
  }

  #if canImport(ImageIO)
  @Test func imageIOReadsTheSamePixels() throws {
    let pixels = try #require(BlurHash.decode(exampleHashes[3], width: 24, height: 16))
    let file = pixels.png()
    let data = try #require(CFDataCreate(nil, file, file.count))
    let source = try #require(CGImageSourceCreateWithData(data, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(image.width == 24 && image.height == 16)
    var read = [UInt8](repeating: 0, count: 24 * 16 * 4)
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    try read.withUnsafeMutableBytes { buffer in
      let context = try #require(CGContext(
        data: buffer.baseAddress, width: 24, height: 16, bitsPerComponent: 8, bytesPerRow: 24 * 4, space: space,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
      context.draw(image, in: CGRect(x: 0, y: 0, width: 24, height: 16))
    }
    for offset in stride(from: 0, to: read.count, by: 4) {
      #expect(read[offset..<offset + 3] == pixels.rgba[offset..<offset + 3])
    }
  }
  #endif
}
