// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "keryx",
    targets: [
        // Platform-independent core: inbox state machine, directory scan,
        // file-watching. Fully unit-tested on Linux (Swift Testing).
        .target(name: "KeryxKit"),
        // macOS menubar shell (NSStatusItem). Guarded with #if os(macOS) so
        // the package still builds and tests on Linux; only produces a
        // placeholder binary there.
        .executableTarget(
            name: "KeryxApp",
            dependencies: ["KeryxKit"]
        ),
        .testTarget(
            name: "KeryxKitTests",
            dependencies: ["KeryxKit"]
        ),
    ]
)