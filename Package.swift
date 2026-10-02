// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacDict",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacDict", targets: ["MacDict"])
    ],
    targets: [
        .executableTarget(
            name: "MacDict",
            path: "Sources/MacDict",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("CoreServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Vision"),
                .linkedFramework("AVFoundation"),
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
