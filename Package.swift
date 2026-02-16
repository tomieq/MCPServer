// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MCPServer",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/tomieq/swifter.git", .upToNextMajor(from: "3.1.1")),
        .package(url: "https://github.com/tomieq/Logger.git", .upToNextMajor(from: "1.1.0")),
        .package(url: "https://github.com/tomieq/SwiftExtensions", .upToNextMajor(from: "2.0.0")),
        .package(url: "https://github.com/aus-der-Technik/FileMonitor.git", from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "MCPServer",
            dependencies: [
                .product(name: "Swifter", package: "Swifter"),
                .product(name: "Logger", package: "Logger"),
                .product(name: "SwiftExtensions", package: "SwiftExtensions"),
                .product(name: "FileMonitor", package: "FileMonitor")
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
