// swift-tools-version:5.2

import PackageDescription

let package = Package(
    name: "Resty",
    platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v6)],
    products: [.library(name: "Resty", targets: ["Resty"])],
    targets: [
        .target(name: "Resty", dependencies: []),
        // .testTarget(name: "RestyTests", dependencies: ["Resty"])
    ]
)
