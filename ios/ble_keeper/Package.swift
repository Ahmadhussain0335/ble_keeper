// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ble_keeper",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "ble-keeper", targets: ["ble_keeper"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "ble_keeper",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                // No required-reason APIs and no collected data; see the file.
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
