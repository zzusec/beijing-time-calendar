// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BeijingTimeCalendar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "BeijingTimeCalendar",
            path: "Sources/BeijingTimeCalendar"
        ),
        .testTarget(
            name: "BeijingTimeCalendarTests",
            dependencies: ["BeijingTimeCalendar"],
            path: "Tests/BeijingTimeCalendarTests"
        )
    ]
)
