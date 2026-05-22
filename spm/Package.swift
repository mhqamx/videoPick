// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DouyinDownLoadSPM",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "DouyinDownLoadSPM",
            targets: ["DouyinDownLoadSPM"]
        ),
    ],
    targets: [
        .target(
            name: "DouyinDownLoadSPM",
            path: "Sources/DouyinDownLoadSPM"
        ),
        .testTarget(
            name: "DouyinDownLoadSPMTests",
            dependencies: ["DouyinDownLoadSPM"],
            path: "Tests/DouyinDownLoadSPMTests"
        ),
    ]
)
