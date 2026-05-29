// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SlideRev",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SlideRev", targets: ["SlideRev"])
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
        .package(url: "https://github.com/RevenueCat/purchases-ios.git", from: "5.0.0")
    ],
    targets: [
        .executableTarget(
            name: "SlideRev",
            dependencies: [
                "ZIPFoundation",
                .product(name: "RevenueCat", package: "purchases-ios")
            ],
            path: "Sources/SlideRev"
        ),
        .testTarget(
            name: "SlideRevTests",
            dependencies: ["SlideRev"],
            path: "Tests",
            exclude: [
                "test_core.py",
                "test_main.swift",
                "NeuralInpainterTests.swift",
                "MemoryModelTests.swift"
            ]
        )
    ]
)
