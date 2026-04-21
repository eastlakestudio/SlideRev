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
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19")
    ],
    targets: [
        .executableTarget(
            name: "SlideRev",
            dependencies: [
                "ZIPFoundation"
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
