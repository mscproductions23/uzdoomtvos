// swift-tools-version:5.9
// Vendored from https://github.com/weichsel/ZIPFoundation at 0.9.20
// (revision 22787ffb59de99e5dc1fbfe80b19c97a904ad48d) to fix the deprecated
// `.watchOS(.v4)` platform declaration in the upstream manifest.
import PackageDescription

let package = Package(
    name: "ZIPFoundation",
    platforms: [
        .macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v9), .visionOS(.v1)
    ],
    products: [
        .library(name: "ZIPFoundation", targets: ["ZIPFoundation"])
    ],
    targets: [
        .target(name: "ZIPFoundation",
                resources: [
                    .copy("Resources/PrivacyInfo.xcprivacy")
                ])
    ]
)
