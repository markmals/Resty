// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "Resty",
    platforms: [.iOS(.v13), .macOS(.v10_15)],
    products: [.library(name: "Resty", targets: ["Resty"])],
    targets: [
        .target(name: "Resty", dependencies: []),
        // .testTarget(name: "RestyTests", dependencies: ["Resty"])
    ]
)
