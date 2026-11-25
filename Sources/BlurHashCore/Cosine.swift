/// cos(pi * numerator / denominator) without a math library, which Embedded Swift does not have.
///
/// The BlurHash basis functions only ever take rational multiples of pi, so the angle is reduced exactly, in integers,
/// to [0, pi/4], where a Taylor series of nine terms is accurate to the last bit or two of a double.
@inline(__always)
func cosPi(_ numerator: Int, over denominator: Int) -> Double {
  let period = 2 * denominator
  var k = numerator % period
  if k < 0 { k += period }
  // cos(2 pi - a) = cos(a): k in 0...denominator, the angle in [0, pi].
  if k > denominator { k = period - k }
  // cos(pi - a) = -cos(a): the angle in [0, pi/2].
  var sign = 1.0
  if 2 * k > denominator {
    k = denominator - k
    sign = -1
  }
  // cos(a) = sin(pi/2 - a): the argument in [0, pi/4].
  if 4 * k > denominator {
    return sign * sineSeries(Double.pi * Double(denominator - 2 * k) / Double(2 * denominator))
  }
  return sign * cosineSeries(Double.pi * Double(k) / Double(denominator))
}

/// cos(x) for x in [0, pi/4].
@inline(__always)
private func cosineSeries(_ x: Double) -> Double {
  let square = x * x
  var term = 1.0
  var sum = 1.0
  var n = 1
  while n <= 9 {
    term *= -square / Double((2 * n - 1) * (2 * n))
    sum += term
    n += 1
  }
  return sum
}

/// sin(x) for x in [0, pi/4].
@inline(__always)
private func sineSeries(_ x: Double) -> Double {
  let square = x * x
  var term = x
  var sum = x
  var n = 1
  while n <= 9 {
    term *= -square / Double((2 * n) * (2 * n + 1))
    sum += term
    n += 1
  }
  return sum
}
