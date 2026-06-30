// swift-tools-version: 6.1

import Foundation
import PackageDescription

let nativeVersion = "0.5.1"
let localArtifact = "Artifacts/CZvec.xcframework"
let nativeTarget: Target =
    if FileManager.default.fileExists(atPath: localArtifact) {
        .binaryTarget(name: "CZvec", path: localArtifact)
    } else {
        .binaryTarget(
            name: "CZvec",
            url:
                "https://github.com/lurenyang418/zvec-swift/releases/download/native-v\(nativeVersion)/CZvec.xcframework.zip",
            // Replaced by scripts/update-checksum.sh after publishing native-v0.5.1.
            checksum: "4d87cfc467d9b8bf2420bd04b5d4a59fc2ff9396be55a4c75ba836511bb82b50"
        )
    }

let package = Package(
    name: "zvec-swift",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "Zvec", targets: ["Zvec"]),
        .executable(name: "zvec-example", targets: ["ZvecExample"]),
    ],
    targets: [
        nativeTarget,
        .target(
            name: "Zvec",
            dependencies: ["CZvec"],
            resources: [.copy("Resources/jieba_dict")],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .executableTarget(name: "ZvecExample", dependencies: ["Zvec"]),
        .testTarget(name: "ZvecTests", dependencies: ["Zvec"]),
    ],
    swiftLanguageModes: [.v6]
)
