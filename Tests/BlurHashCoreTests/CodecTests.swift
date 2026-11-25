@testable import BlurHashCore
import Testing

/// The bytes of a hex string.
func bytes(hex: String) -> [UInt8] {
  let digits = Array(hex.utf8)
  func value(_ digit: UInt8) -> UInt8 { digit <= 57 ? digit - 48 : digit - 87 }
  var result: [UInt8] = []
  result.reserveCapacity(digits.count / 2)
  var index = 0
  while index + 1 < digits.count {
    result.append(value(digits[index]) << 4 | value(digits[index + 1]))
    index += 2
  }
  return result
}

@Suite struct DecodeTests {
  @Test(arguments: decodeFixtures.indices)
  func matchesTheReferenceDecoder(fixture index: Int) throws {
    let fixture = decodeFixtures[index]
    let pixels = try #require(BlurHash.decode(fixture.hash, width: fixture.width, height: fixture.height))
    let expected = bytes(hex: fixture.pixels)
    #expect(pixels.width == fixture.width && pixels.height == fixture.height)
    #expect(pixels.rgba.count == expected.count)
    var largest = 0
    var different = 0
    for (actual, reference) in zip(pixels.rgba, expected) where actual != reference {
      different += 1
      largest = max(largest, abs(Int(actual) - Int(reference)))
    }
    // The reference sums the basis in another order with the platform's cos; only a value that lands on a rounding
    // boundary may round the other way.
    #expect(largest <= 1, "a channel differs by \(largest)")
    #expect(different * 1000 <= expected.count, "\(different) of \(expected.count) bytes differ")
  }

  @Test func alphaIsOpaque() throws {
    let pixels = try #require(BlurHash.decode(exampleHashes[0], width: 7, height: 5))
    for index in stride(from: 3, to: pixels.rgba.count, by: 4) { #expect(pixels.rgba[index] == 255) }
  }

  @Test func zeroPunchIsTheAverageColor() throws {
    let hash = exampleHashes[1]
    let pixels = try #require(BlurHash.decode(hash, width: 6, height: 4, punch: 0))
    let average = try #require(BlurHash.averageColor(hash))
    for offset in stride(from: 0, to: pixels.rgba.count, by: 4) {
      #expect(pixels.rgba[offset] == average.red)
      #expect(pixels.rgba[offset + 1] == average.green)
      #expect(pixels.rgba[offset + 2] == average.blue)
    }
  }

  @Test func punchScalesTheDetails() throws {
    let hash = exampleHashes[0]
    func spread(_ punch: Double) throws -> Int {
      let pixels = try #require(BlurHash.decode(hash, width: 16, height: 16, punch: punch))
      var low = 255
      var high = 0
      for offset in stride(from: 0, to: pixels.rgba.count, by: 4) {
        low = min(low, Int(pixels.rgba[offset]))
        high = max(high, Int(pixels.rgba[offset]))
      }
      return high - low
    }
    #expect(try spread(0.5) < spread(1))
    #expect(try spread(1) < spread(2))
    #expect(BlurHash.decode(hash, width: 8, height: 8) == BlurHash.decode(hash, width: 8, height: 8, punch: 1))
  }

  @Test func aSquareDecodeStretchedIsTheDecodeAtTheFrameSize() throws {
    // The basis functions take the position as a fraction of the frame, so the same columns of a 30 by 10 image and of
    // a 30 by 30 one hold the same colors at the same fractions of the height.
    let hash = exampleHashes[2]
    let wide = try #require(BlurHash.decode(hash, width: 30, height: 10))
    let square = try #require(BlurHash.decode(hash, width: 30, height: 30))
    for row in 0..<10 {
      for column in 0..<30 {
        let wideOffset = (row * 30 + column) * 4
        let squareOffset = (row * 3 * 30 + column) * 4
        #expect(wide.rgba[wideOffset..<wideOffset + 4] == square.rgba[squareOffset..<squareOffset + 4])
      }
    }
  }

  @Test(arguments: [
    "", "LEHV6", "LEHV6nWB2yk8pyo0adR*.7kCMdn", "LEHV6nWB2yk8pyo0adR*.7kCMdnjj", "LEHV6nWB2yk8pyo0adR*.7kCMdn\"",
    "LEHV6nWB2yk8pyo0adR*.7kCMdné", "LEHV6nWB2yk8pyo0adR*.7kCMd/j", " EHV6nWB2yk8pyo0adR*.7kCMdnj",
  ])
  func rejectsMalformedHashes(_ hash: String) {
    #expect(!BlurHash.isValid(hash))
    #expect(BlurHash.decode(hash, width: 4, height: 4) == nil)
    #expect(BlurHash.components(hash) == nil)
    #expect(BlurHash.averageColor(hash) == nil)
  }

  @Test func rejectsSizesThatAreNotPositive() {
    #expect(BlurHash.decode(exampleHashes[0], width: 0, height: 4) == nil)
    #expect(BlurHash.decode(exampleHashes[0], width: 4, height: -1) == nil)
  }

  @Test func readsTheHeader() throws {
    for hash in exampleHashes {
      let components = try #require(BlurHash.components(hash))
      #expect(components.x == 4 && components.y == 3)
    }
    let nine = try #require(encodeFixtures.first { $0.componentsX == 9 })
    let components = try #require(BlurHash.components(nine.hash))
    #expect(components.x == 9 && components.y == 9)
    // "LEHV6n...": the four digits after the size flag and the maximum, "HV6n", are the average color.
    let average = try #require(BlurHash.averageColor(exampleHashes[0]))
    let dc = 17 * 83 * 83 * 83 + 31 * 83 * 83 + 6 * 83 + 49  // "H", "V", "6", "n"
    #expect(average == BlurHashColor(red: UInt8(dc >> 16), green: UInt8((dc >> 8) & 255), blue: UInt8(dc & 255)))
  }
}

@Suite struct EncodeTests {
  @Test(arguments: encodeFixtures.indices)
  func matchesTheReferenceEncoder(fixture index: Int) {
    let fixture = encodeFixtures[index]
    let hash = BlurHash.encode(
      rgba: bytes(hex: fixture.pixels), width: fixture.width, height: fixture.height,
      componentsX: fixture.componentsX, componentsY: fixture.componentsY)
    #expect(hash == fixture.hash)
  }

  @Test func decodingAnEncodedImageGivesItBack() throws {
    // Re-encoding a decoded image keeps its average (to one step of rounding) and its look; not every component, as the
    // basis is not orthogonal on the pixel grid (see aFlatImageKeepsItsAverage).
    for hash in exampleHashes {
      let pixels = try #require(BlurHash.decode(hash, width: 32, height: 32))
      let encoded = try #require(BlurHash.encode(pixels))
      let again = try #require(BlurHash.decode(encoded, width: 32, height: 32))
      let before = try #require(BlurHash.averageColor(hash))
      let after = try #require(BlurHash.averageColor(encoded))
      #expect(abs(Int(before.red) - Int(after.red)) <= 1 && abs(Int(before.green) - Int(after.green)) <= 1
              && abs(Int(before.blue) - Int(after.blue)) <= 1)
      var total = 0
      for (a, b) in zip(pixels.rgba, again.rgba) { total += abs(Int(a) - Int(b)) }
      #expect(total <= 10 * pixels.rgba.count, "\(hash) -> \(encoded): mean difference \(total / pixels.rgba.count)")
    }
  }

  @Test func rejectsBadArguments() {
    let pixels = BlurHashPixels(width: 2, height: 2, rgba: [UInt8](repeating: 128, count: 16))
    #expect(BlurHash.encode(pixels, componentsX: 0, componentsY: 3) == nil)
    #expect(BlurHash.encode(pixels, componentsX: 4, componentsY: 10) == nil)
    #expect(BlurHash.encode(rgba: [UInt8](repeating: 0, count: 15), width: 2, height: 2) == nil)
    #expect(BlurHash.encode(rgba: [], width: 0, height: 0) == nil)
  }

  @Test func aFlatImageKeepsItsAverage() throws {
    // The basis functions sample cos(pi * x * i / width) at the left edge of each pixel, so they are not orthogonal on the
    // pixel grid and even a flat image gets small AC components (about 2 / width of its intensity). That is the format
    // (the reference encoders give the same hashes); the average is exact and the error fades with the size.
    for (side, bound) in [(32, 20), (100, 8)] {
      let pixels = BlurHashPixels(width: side, height: side, rgba: [UInt8](repeating: 200, count: side * side * 4))
      let hash = try #require(BlurHash.encode(pixels))
      #expect(BlurHash.averageColor(hash) == BlurHashColor(red: 200, green: 200, blue: 200))
      let decoded = try #require(BlurHash.decode(hash, width: side, height: side))
      var largest = 0
      for offset in stride(from: 0, to: decoded.rgba.count, by: 4) {
        for channel in 0..<3 { largest = max(largest, abs(Int(decoded.rgba[offset + channel]) - 200)) }
      }
      #expect(largest <= bound, "\(side) pixels: a channel is off by \(largest)")
    }
  }
}
