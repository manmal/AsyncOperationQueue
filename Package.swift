// swift-tools-version: 5.6

import PackageDescription

let package = Package(
    name: "AsyncOperationQueue",
    platforms: [.iOS(.v13), .macOS(.v10_15)],
    products: [
        .library(
            name: "AsyncOperationQueue",
            targets: ["AsyncOperationQueue"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-custom-dump.git", from: "0.5.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.0.2"),
        // .package(url: "https://github.com/MarcoEidinger/SwiftFormatPlugin", from: "0.49.15")
    ],
    targets: [
        .target(
            name: "AsyncOperationQueue",
            dependencies: [
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "CustomDump", package: "swift-custom-dump"),
            ]),
        .testTarget(
            name: "AsyncOperationQueueTests",
            dependencies: ["AsyncOperationQueue"]),
    ]
)
