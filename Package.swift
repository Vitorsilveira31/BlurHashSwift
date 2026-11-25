// swift-tools-version: 6.0
import PackageDescription

// BlurHashSwift: a BlurHash codec in plain Swift (BlurHashCore) and a SwiftUI placeholder view (BlurHashSwift) for
// Apple's SwiftUI, Skip on Android and SwiftUIWeb in the browser. One source tree; the environment picks the UI layer:
//
//  - Default: Apple platforms, with nothing to fetch.
//  - TARGET_OS_ANDROID (set by Skip's Android build): `import SwiftUI` is Skip Fuse's, from skip-fuse-ui.
//  - SWIFTUIWEB_EMBEDDED (set by SwiftUIWeb's browser build), or BLURHASHSWIFT_SWIFTUIWEB=1 for a native build against
//    SwiftUIWeb: the view is SwiftUIWeb's.
let environment = Context.environment
let isAndroid = (environment["TARGET_OS_ANDROID"] ?? "0") != "0"
let isWeb = environment["SWIFTUIWEB_EMBEDDED"] != nil || environment["BLURHASHSWIFT_SWIFTUIWEB"] == "1"

let package = Package(
  name: "BlurHashSwift",
  platforms: [.iOS(.v16), .macOS(.v13), .tvOS(.v16), .watchOS(.v9), .visionOS(.v1)],
  products: [
    // The placeholder view and modifier; re-exports BlurHashCore.
    .library(name: "BlurHashSwift", targets: ["BlurHashSwift"]),
    // Decoding, encoding and the cache only: no UI, no Foundation (it compiles under Embedded Swift).
    .library(name: "BlurHashCore", targets: ["BlurHashCore"]),
  ],
  targets: [
    // On Linux x86_64 the compiler lowers `rounded(.down)` to libm's `floor` (no SSE4.1 rounding instruction is assumed),
    // and nothing else links libm into an executable that does not import Glibc.
    .target(name: "BlurHashCore", linkerSettings: [.linkedLibrary("m", .when(platforms: [.linux]))]),
    .target(name: "BlurHashSwift", dependencies: ["BlurHashCore"]),
    .testTarget(name: "BlurHashCoreTests", dependencies: ["BlurHashCore"]),
    .testTarget(name: "BlurHashSwiftTests", dependencies: ["BlurHashSwift"]),
    // `swift run -c release BlurHashBenchmark`: decode and encode times.
    .executableTarget(name: "BlurHashBenchmark", dependencies: ["BlurHashCore"], path: "Benchmarks/BlurHashBenchmark"),
  ]
)

@MainActor func target(_ name: String) -> Target { package.targets.first { $0.name == name }! }

if isWeb {
  // SwiftUIWeb's own minimum for a native build; the browser build sets none.
  package.platforms = environment["SWIFTUIWEB_EMBEDDED"] != nil ? nil : [.macOS(.v15)]
  package.dependencies = [.package(url: "https://github.com/Vitorsilveira31/SwiftUIWeb.git", from: "0.1.40")]
  target("BlurHashSwift").dependencies.append(.product(name: "SwiftUIWeb", package: "swiftuiweb"))
  if environment["SWIFTUIWEB_EMBEDDED"] != nil {
    // The browser build compiles libraries only.
    package.targets.removeAll { $0.type == .test || $0.type == .executable }
  }
} else if isAndroid {
  package.dependencies = [.package(url: "https://github.com/skiptools/skip-fuse-ui.git", from: "1.0.0")]
  target("BlurHashSwift").dependencies.append(.product(name: "SkipFuseUI", package: "skip-fuse-ui"))
}
