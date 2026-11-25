/// The base 83 digits of BlurHash.
enum Base83 {
  /// The 83 characters, in digit order.
  static let alphabet: [UInt8] = Array(
    "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~".utf8)

  /// The digit of every ASCII byte, or -1.
  static let digits: [Int8] = {
    var table = [Int8](repeating: -1, count: 128)
    var index = 0
    while index < alphabet.count {
      table[Int(alphabet[index])] = Int8(index)
      index += 1
    }
    return table
  }()

  /// The value of `length` digits from `start`, or nil when one of them is not a digit.
  @inline(__always)
  static func decode(_ bytes: UnsafeBufferPointer<UInt8>, from start: Int, length: Int) -> Int? {
    var value = 0
    var index = start
    while index < start + length {
      let byte = bytes[index]
      guard byte < 128 else { return nil }
      let digit = digits[Int(byte)]
      guard digit >= 0 else { return nil }
      value = value * 83 + Int(digit)
      index += 1
    }
    return value
  }

  /// Appends `value` as `length` digits, most significant first.
  static func encode(_ value: Int, length: Int, into output: inout [UInt8]) {
    var divisor = 1
    var count = 1
    while count < length {
      divisor *= 83
      count += 1
    }
    var remaining = value
    while divisor > 0 {
      output.append(alphabet[(remaining / divisor) % 83])
      remaining %= divisor
      divisor /= 83
    }
  }
}
