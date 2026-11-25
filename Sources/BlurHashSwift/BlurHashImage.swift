// One view, three platform images. The hash is decoded once into a small bitmap (BlurHashCore) and shown as an image
// that the platform scales with bilinear filtering, so the soft gradient comes from the scaling: a resize redraws
// nothing, and there is no Canvas or blur filter to run.
//
//   Apple (SwiftUI):          a CGImage of the pixels in Image(decorative:scale:), .resizable().interpolation(.medium).
//   Android (Skip Fuse):      a UIImage of the PNG, which Skip holds as an android.graphics.Bitmap and draws with a
//                             Compose BitmapPainter (bilinear, FilterQuality.Low).
//   Browser (SwiftUIWeb):     an <img> of the PNG as a data: URL (Image(decorative:), so alt is empty), scaled by
//                             the browser's compositor.
//
// Where there is no SwiftUI at all (Linux without SwiftUIWeb), the module only re-exports the codec.
@_exported import BlurHashCore

#if canImport(SwiftUIWeb) || canImport(SwiftUI)
#if canImport(SwiftUIWeb)
import SwiftUIWeb
#else
import SwiftUI
#endif
#if canImport(SwiftUIWeb)
#elseif os(Android)
import Foundation
import SkipBridge
#elseif canImport(CoreGraphics)
import CoreGraphics
#endif

/// The image a BlurHash describes, filling its frame: a placeholder to show while the real image loads.
///
/// ```swift
/// BlurHashImage(hash: "LEHV6nWB2yk8pyo0adR*.7kCMdnj")
///   .frame(width: 120, height: 180)
/// ```
///
/// The hash is decoded once per hash and resolution, on first display, and kept in ``BlurHashImageCache``. A malformed
/// hash shows nothing (a clear color that still takes the frame).
public struct BlurHashImage: View {
  let key: BlurHashKey

  /// - Parameters:
  ///   - hash: The BlurHash string.
  ///   - resolution: The width and height of the decoded bitmap, in pixels. The platform scales it up smoothly, so 32
  ///     is enough for any frame; 16 halves the memory and suits small thumbnails.
  ///   - punch: The contrast of the details: above 1 stronger, below 1 softer.
  public init(hash: String, resolution: Int = 32, punch: Double = 1) {
    let side = min(max(resolution, 1), 256)
    key = BlurHashKey(hash: hash, width: side, height: side, punch: punch)
  }

  public var body: some View {
    if let image = BlurHashImageCache.image(for: key) {
      image
        .resizable()
        .interpolation(.medium)
        .accessibilityHidden(true)
    } else {
      Color.clear
    }
  }
}

#if os(Android)
/// Skip Fuse shows a native view through its Compose counterpart, `Java_view`, which Skip's build plugin generates for
/// the views of the modules it processes. This library is built without the plugin, so an app that only targets Apple
/// platforms fetches nothing of Skip's; the view has no state, so its counterpart is simply its body's.
extension BlurHashImage: SkipUIBridging {
  public nonisolated var Java_view: any SkipUI.View {
    SkipBridge.assumeMainActorUnchecked { body.Java_viewOrEmpty }
  }
}
#endif

extension View {
  /// Shows the image `hash` describes behind this view, filling its frame: the placeholder of an image that loads over
  /// it. Nothing is drawn when `hash` is nil.
  ///
  /// ```swift
  /// AsyncImage(url: poster.url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
  ///   .frame(width: 120, height: 180)
  ///   .blurHashPlaceholder(poster.blurHash)
  ///   .clipped()
  /// ```
  ///
  /// The placeholder is a static image, so keeping it mounted under the loaded image costs nothing after the first
  /// frame.
  public func blurHashPlaceholder(_ hash: String?, resolution: Int = 32, punch: Double = 1) -> some View {
    background {
      if let hash {
        BlurHashImage(hash: hash, resolution: resolution, punch: punch)
      }
    }
  }
}

#if canImport(SwiftUIWeb)
/// The PNG of a decoded image as a `data:` URL, which the browser shows in an `<img>`.
typealias PlatformImage = String
#elseif os(Android)
/// Skip's UIImage, which holds an `android.graphics.Bitmap` decoded from the PNG.
typealias PlatformImage = UIImage
#elseif canImport(CoreGraphics)
typealias PlatformImage = CGImage
#endif

/// The platform images of decoded hashes, shared by every ``BlurHashImage``.
@MainActor
public enum BlurHashImageCache {
  private static let images = BlurHashCache<PlatformImage>()

  /// The most images kept (256 by default; a 32 by 32 image is 4 KB). The least recently shown go first.
  public static var countLimit: Int {
    get { images.countLimit }
    set { images.countLimit = newValue }
  }

  /// The number of images kept.
  public static var count: Int { images.count }

  /// Forgets every image; they are decoded again when next shown.
  public static func removeAll() {
    images.removeAll()
  }

  /// The image for `key`, decoded and kept on first use, or nil when the hash is malformed.
  static func image(for key: BlurHashKey) -> Image? {
    guard let image = platformImage(for: key) else { return nil }
    #if canImport(SwiftUIWeb)
    return Image(decorative: image)
    #elseif os(Android)
    return Image(uiImage: image)
    #elseif canImport(CoreGraphics)
    return Image(decorative: image, scale: 1)
    #endif
  }

  static func platformImage(for key: BlurHashKey) -> PlatformImage? {
    images.value(for: key) {
      BlurHash.decode(key.hash, width: key.width, height: key.height, punch: key.punch).flatMap(makePlatformImage)
    }
  }

  static func makePlatformImage(_ pixels: BlurHashPixels) -> PlatformImage? {
    #if canImport(SwiftUIWeb)
    return pixels.pngDataURL()
    #elseif os(Android)
    return UIImage(data: Data(pixels.png()))
    #elseif canImport(CoreGraphics)
    // An sRGB image of the opaque RGBA bytes, without a copy through an encoded file.
    guard let data = CFDataCreate(nil, pixels.rgba, pixels.rgba.count),
          let provider = CGDataProvider(data: data),
          let space = CGColorSpace(name: CGColorSpace.sRGB)
    else { return nil }
    return CGImage(
      width: pixels.width, height: pixels.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: pixels.width * 4,
      space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
      decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    #endif
  }
}
#endif
