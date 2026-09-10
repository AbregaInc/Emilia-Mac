// swift-tools-version: 6.0
import PackageDescription
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let whisper = root + "/.deps/whisper.cpp"

let package = Package(
    name: "Emilia",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "Emilia", targets: ["Emilia"]), .library(name: "EmiliaCore", targets: ["EmiliaCore"])],
    targets: [
        .target(name: "EmiliaCore"),
        .target(name: "CWhisperBridge", publicHeadersPath: "include",
                cxxSettings: [.unsafeFlags(["-I" + whisper + "/include", "-I" + whisper + "/ggml/include"])],
                linkerSettings: [.unsafeFlags(["-L" + whisper + "/build/src", "-L" + whisper + "/build/ggml/src", "-L" + whisper + "/build/ggml/src/ggml-metal", "-L" + whisper + "/build/ggml/src/ggml-blas"]),
                    .linkedLibrary("whisper"), .linkedLibrary("ggml"), .linkedLibrary("ggml-base"), .linkedLibrary("ggml-cpu"), .linkedLibrary("ggml-metal"), .linkedLibrary("ggml-blas"), .linkedLibrary("c++"),
                    .linkedFramework("Accelerate"), .linkedFramework("Metal"), .linkedFramework("Foundation")]),
        .executableTarget(name: "Emilia", dependencies: ["EmiliaCore", "CWhisperBridge"]),
        .executableTarget(name: "EmiliaCheck", dependencies: ["EmiliaCore", "CWhisperBridge"]),
        .testTarget(name: "EmiliaCoreTests", dependencies: ["EmiliaCore"]),
        .testTarget(name: "EmiliaAppTests", dependencies: ["Emilia"])
    ],
    swiftLanguageModes: [.v5], cxxLanguageStandard: .cxx17
)
