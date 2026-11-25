@testable import BlurHashCore
import Testing

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#endif

// The codec does without a math library; these tests hold its replacements to the platform's `cos` and `pow`.

@Suite struct MathTests {
  @Test func cosineMatchesTheMathLibrary() {
    var largest = 0.0
    for denominator in [1, 2, 3, 5, 7, 12, 16, 31, 32, 100, 255, 1000, 4096] {
      for numerator in -2 * denominator...(9 * denominator + 3) {
        // The library is given the angle reduced to [0, pi] in integers, as cosPi reduces it: pi * n / d rounds to
        // the nearest double, whose error grows with n (4e-15 at n / d = 9) and is not the error of cosPi.
        let turn = (numerator % (2 * denominator) + 2 * denominator) % (2 * denominator)
        let reduced = min(turn, 2 * denominator - turn)
        let expected = cos(Double.pi * Double(reduced) / Double(denominator))
        largest = max(largest, abs(cosPi(numerator, over: denominator) - expected))
      }
    }
    // Both sides round pi * k / d to a double (an error up to pi * 2^-52 / 2 at k = d), so they agree to about 1e-15.
    #expect(largest < 1.5e-15, "largest error \(largest)")
  }

  @Test func linearTableIsTheSpecificationsFormula() {
    for byte in 0...255 {
      let v = Double(byte) / 255
      let expected = v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
      let actual = SRGB.linearFromByte[byte]
      #expect(abs(actual - expected) <= 2 * expected.ulp, "byte \(byte): \(actual) vs \(expected)")
    }
  }

  @Test func byteThresholdsAreWhereTheSpecificationRoundsUp() {
    func linearTosRGB(_ value: Double) -> Int {
      let v = max(0, min(1, value))
      let scaled = v <= 0.0031308 ? v * 12.92 * 255 + 0.5 : (1.055 * pow(v, 1 / 2.4) - 0.055) * 255 + 0.5
      return Int(scaled.rounded(.towardZero))
    }
    #expect(SRGB.byteThresholds.count == 255)
    for (byte, threshold) in SRGB.byteThresholds.enumerated() {
      // Two units in the last place either side: a platform `pow` may differ from JavaScript's by one.
      #expect(linearTosRGB(threshold.nextUp.nextUp) == byte + 1, "threshold \(byte)")
      #expect(linearTosRGB(threshold.nextDown.nextDown) == byte, "threshold \(byte)")
    }
  }

  @Test func byteOfLinearIsTheSpecificationsRounding() {
    func linearTosRGB(_ value: Double) -> UInt8 {
      let v = max(0, min(1, value))
      let scaled = v <= 0.0031308 ? v * 12.92 * 255 + 0.5 : (1.055 * pow(v, 1 / 2.4) - 0.055) * 255 + 0.5
      return UInt8(scaled.rounded(.towardZero))
    }
    var different = 0
    let samples = 200_000
    for index in -1000...samples + 1000 {
      let value = Double(index) / Double(samples)
      if BlurHash.sRGBByte(value) != linearTosRGB(value) { different += 1 }
    }
    #expect(different == 0)
    #expect(BlurHash.sRGBByte(-1) == 0 && BlurHash.sRGBByte(2) == 255)
  }

  @Test func linearOfEveryByteRoundsBackToIt() {
    for byte in 0...255 { #expect(BlurHash.sRGBByte(SRGB.linearFromByte[byte]) == UInt8(byte)) }
  }
}

@Suite struct ByteLookupTests {
  @Test func aBinHoldsAtMostOneThreshold() {
    for (low, high) in zip(SRGB.byteThresholds, SRGB.byteThresholds.dropFirst()) {
      #expect(high - low > 1 / Double(SRGB.binCount))
    }
  }

  @Test func theLookupCountsTheThresholdsBelowTheValue() {
    // At and next to every threshold and every bin edge, the lookup equals a plain count of the thresholds <= value.
    var values: [Double] = [-1, 0, 1, 2, .infinity, -.infinity]
    for threshold in SRGB.byteThresholds { values += [threshold.nextDown, threshold, threshold.nextUp] }
    for bin in 0...SRGB.binCount {
      let edge = Double(bin) / Double(SRGB.binCount)
      values += [edge.nextDown, edge, edge.nextUp]
    }
    for value in values {
      var count = 0
      for threshold in SRGB.byteThresholds where threshold <= value { count += 1 }
      #expect(BlurHash.sRGBByte(value) == UInt8(count), "\(value)")
    }
    #expect(BlurHash.sRGBByte(.nan) == 0)
  }
}
