// The view on Apple platforms, rendered with SwiftUI's ImageRenderer and read back pixel by pixel.
#if canImport(SwiftUI) && canImport(CoreGraphics)
@testable import BlurHashSwift
import CoreGraphics
import SwiftUI
import Testing

let hash = "LGF5]+Yk^6#M@-5c,1J5@[or[Q6."

/// RGBA bytes of `image` drawn into an sRGB bitmap of its size.
func rgba(of image: CGImage) throws -> [UInt8] {
  var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
  let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
  try bytes.withUnsafeMutableBytes { buffer in
    let context = try #require(CGContext(
      data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
      bytesPerRow: image.width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
  }
  return bytes
}

@MainActor
func render<Content: View>(_ view: Content, width: Int, height: Int) throws -> [UInt8] {
  let renderer = ImageRenderer(content: view.frame(width: CGFloat(width), height: CGFloat(height)))
  renderer.scale = 1
  let image = try #require(renderer.cgImage)
  #expect(image.width == width && image.height == height)
  return try rgba(of: image)
}

@MainActor
@Suite(.serialized) struct RenderTests {
  @Test func theCGImageHoldsTheDecodedPixels() throws {
    let pixels = try #require(BlurHash.decode(hash, width: 32, height: 32))
    let image = try #require(BlurHashImageCache.makePlatformImage(pixels))
    #expect(image.width == 32 && image.height == 32)
    let read = try rgba(of: image)
    for offset in stride(from: 0, to: read.count, by: 4) {
      #expect(read[offset..<offset + 4] == pixels.rgba[offset..<offset + 4])
    }
  }

  @Test func fillsItsFrameWithTheImageScaledSmoothly() throws {
    let width = 160
    let height = 240
    let rendered = try render(BlurHashImage(hash: hash), width: width, height: height)
    // Scaled with bilinear filtering, the 32 by 32 bitmap is close to the hash decoded at the full size: a nearest
    // neighbour scaling would leave steps between the 5 by 7.5 point blocks.
    let reference = try #require(BlurHash.decode(hash, width: width, height: height))
    var largest = 0
    var total = 0
    for offset in stride(from: 0, to: rendered.count, by: 4) {
      #expect(rendered[offset + 3] == 255)
      for channel in 0..<3 {
        let difference = abs(Int(rendered[offset + channel]) - Int(reference.rgba[offset + channel]))
        largest = max(largest, difference)
        total += difference
      }
    }
    let mean = Double(total) / Double(width * height * 3)
    #expect(largest <= 12, "largest difference \(largest)")
    #expect(mean <= 2, "mean difference \(mean)")
    // Smoothness: neighbouring pixels of a row differ by little.
    var step = 0
    for row in 0..<height {
      for column in 1..<width {
        let offset = (row * width + column) * 4
        for channel in 0..<3 { step = max(step, abs(Int(rendered[offset + channel]) - Int(rendered[offset - 4 + channel]))) }
      }
    }
    #expect(step <= 5, "largest step between neighbours \(step)")
  }

  @Test func nearestNeighbourScalingWouldShowSteps() throws {
    // The counterpart of the test above, so it is known to tell the two apart.
    let pixels = try #require(BlurHash.decode(hash, width: 32, height: 32))
    let image = try #require(BlurHashImageCache.makePlatformImage(pixels))
    let view = Image(decorative: image, scale: 1).resizable().interpolation(.none)
    let rendered = try render(view, width: 160, height: 240)
    var step = 0
    for row in 0..<240 {
      for column in 1..<160 {
        let offset = (row * 160 + column) * 4
        for channel in 0..<3 { step = max(step, abs(Int(rendered[offset + channel]) - Int(rendered[offset - 4 + channel]))) }
      }
    }
    #expect(step >= 10, "largest step between neighbours \(step)")
  }

  @Test func theModifierDrawsBehindTheContent() throws {
    let behind = try render(Color.clear.blurHashPlaceholder(hash), width: 40, height: 40)
    #expect(behind[3] == 255)
    let over = try render(Color.red.blurHashPlaceholder(hash), width: 40, height: 40)
    #expect(over[0] > 200 && over[1] < 100 && over[2] < 100)
    // Nothing behind: the blue under it shows. (A fully transparent render may hand back a reused buffer of the same
    // size, so the case is drawn over an opaque color.)
    let none = try render(Color.clear.blurHashPlaceholder(nil).background(Color.blue), width: 40, height: 40)
    #expect(none[0] < 60 && none[2] > 200)
  }

  @Test func aMalformedHashShowsNothing() throws {
    let rendered = try render(BlurHashImage(hash: "not a hash"), width: 20, height: 20)
    #expect(rendered.allSatisfy { $0 == 0 })
  }

  @Test func decodesOncePerHashAndResolution() throws {
    BlurHashImageCache.removeAll()
    for _ in 0..<3 { _ = try render(BlurHashImage(hash: hash), width: 30, height: 30) }
    #expect(BlurHashImageCache.count == 1)
    _ = try render(BlurHashImage(hash: hash, resolution: 16), width: 30, height: 30)
    #expect(BlurHashImageCache.count == 2)
  }
}
#endif
