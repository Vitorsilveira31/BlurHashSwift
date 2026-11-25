// swift-tools-version: 6.1
import PackageDescription

// A Skip Fuse app that shows BlurHashSwift's placeholders on Android, for `Android/demo/check.sh`. It depends on this
// checkout of the library, as an app next to it would. Skip finds a local package by its folder name, so the path ends
// with it: this assumes the checkout is called BlurHashSwift (what `git clone` names it).
let package = Package(
    name: "BlurHashDemo",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BlurHashDemo", type: .dynamic, targets: ["BlurHashDemo"]),
    ],
    dependencies: [
        .package(url: "https://github.com/skiptools/skip.git", from: "1.9.20"),
        .package(url: "https://github.com/skiptools/skip-fuse-ui.git", from: "1.0.0"),
        .package(path: "../../../BlurHashSwift"),
    ],
    targets: [
        .target(name: "BlurHashDemo", dependencies: [
            .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
            .product(name: "BlurHashSwift", package: "BlurHashSwift"),
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
    ]
)
