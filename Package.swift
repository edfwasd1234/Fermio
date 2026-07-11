// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Fremio",
    platforms: [
        .iOS("26.0")
    ],
    products: [
        // An xtool project should contain exactly one library product,
        // representing the main app.
        .library(
            name: "Fremio",
            targets: ["Fremio"]
        ),
    ],
    targets: [
        .target(
            name: "Fremio",
            path: "Sources/Fremio"
        ),
    ]
)
