// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "UniAI",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "UniAI",
            path: "Sources/UniAI",
            exclude: ["Info.plist"],
            linkerSettings: [
                // 将 Info.plist 内嵌进可执行文件，使 `swift run` 也能以正式 App 形态运行
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/UniAI/Info.plist",
                ])
            ]
        )
    ]
)
