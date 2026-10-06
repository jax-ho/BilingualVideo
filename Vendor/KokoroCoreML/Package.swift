// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KokoroCoreML",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "KokoroCoreML", targets: ["KokoroCoreML"])],
    traits: [.default(enabledTraits: [])],
    dependencies: [
        .package(url: "https://github.com/Jud/swift-bart-g2p.git", exact: "0.4.0")
    ],
    targets: [
        .target(name: "KokoroCoreML", dependencies: [
            .product(name: "BARTG2P", package: "swift-bart-g2p")
        ], resources: [.process("Resources")])
    ]
)
