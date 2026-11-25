// swift-tools-version: 6.4
import PackageDescription

// A SwiftUIWeb app that shows BlurHash placeholders, the way an app shares its views with iOS and Android:
// `import SwiftUI` maps to SwiftUIWeb, and `import BlurHashSwift` is the same product as on the other platforms.
// Web/demo/run.sh builds it next to this checkout (`../BlurHashSwift`).
let package = Package(
  name: "BlurHashDemo",
  platforms: [.macOS(.v15)],
  dependencies: [
    .package(url: "https://github.com/Vitorsilveira31/SwiftUIWeb.git", from: "0.1.40"),
    .package(path: "../BlurHashSwift"),
  ],
  targets: [
    .executableTarget(
      name: "BlurHashDemo",
      dependencies: [
        .product(name: "SwiftUIWeb", package: "swiftuiweb"),
        .product(name: "SwiftUIWebBrowser", package: "swiftuiweb"),
        .product(name: "BlurHashSwift", package: "BlurHashSwift"),
      ],
      path: "Sources",
      swiftSettings: [.unsafeFlags(["-module-alias", "SwiftUI=SwiftUIWeb"])]
    )
  ]
)
