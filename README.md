# FSRMetal

[English](README.md) | [简体中文](README-zh.md)

Native Apple Metal FSR 1 spatial upscaling (EASU + optional RCAS) — Swift Package and macOS CLI.

The Swift API enhances `CVPixelBuffer` video frames and `CGImage` images for image
tools, video players and processing pipelines. The macOS CLI upscales images from
a terminal or batch scripts.

The package bundles its Metal library and upstream notices. The shader preserves strict FP32 arithmetic and separate EASU/RCAS passes.

## Requirements

- macOS 13+, iOS 16+, tvOS 16+, visionOS 1+; Metal-capable device.
- Swift 5.10+ / Xcode 15.3+.
- macOS CLI uses ImageIO to read images and writes PNG.
- SDR processing only. HDR/Dolby Vision input is rejected.

## Swift Package usage

Add the v0.1.0 release with Swift Package Manager:

```swift
dependencies: [.package(url: "https://github.com/cinemore/fsr-metal.git", exact: "0.1.0")],
targets: [
    .target(name: "YourTarget", dependencies: [
        .product(name: "FSRMetal", package: "fsr-metal")
    ])
]
```

```swift
import FSRMetal

let upscaler = try FSRUpscaler(outputWidth: 3840, outputHeight: 2160, sharpness: 1)
let output = try upscaler.enhance(pixelBuffer: input)
// CGImage overload for image tools:
let imageOutput = try upscaler.enhance(image: image)
```

The output must enlarge the source without shrinking either dimension. The caller controls aspect ratio through the requested dimensions. RCAS parameter `nil` disables sharpening; `0` is strongest and `2` weakest.

The synchronous high-level API serializes calls, waits for GPU completion and returns independently owned buffers. It accepts BGRA directly and converts other supported CoreVideo formats through VideoToolbox. Source data is not modified; display/color attachments are carried to the output with clean aperture scaled. The CGImage entry point converts image colors to sRGB.

For sibling development checkouts, replace the URL requirement with `.package(path: "../fsr-metal")`.

## Integrating into a GPU pipeline

`FSREngine(device:)` exposes Metal texture encoding on caller-owned output and command buffers. It neither commits nor waits on caller command buffers. Serialize access to one engine and wait for the previous GPU operation to finish before reusing its workspace. Textures must belong to the engine device, be 2D, support the needed shader access, and represent SDR RGB values.

`encode(command:input:output:sharpness:)` preserves separate EASU and optional RCAS passes and reuses its FP32 workspace.

Applications control scheduling, cancellation and output buffer pools when composing video or GPU processing pipelines.

## CLI

```sh
swift run fsr-metal --input input.png --output output.png --width 3840 --height 2160 --sharpness 1
swift run fsr-metal --self-test
swift run fsr-metal --input input.png --output output.png --bench 5
```

Without `--width`/`--height`, the CLI uses 2×. Provide both dimensions together. Use `--no-sharpen` for EASU only.

## Binary releases and Homebrew

The release workflow builds **arm64**, **x86_64** and **universal** archives. Every archive includes `bin/fsr-metal`, its adjacent `FSRMetal_FSRMetal.bundle`, LICENSE and notices. Keep the bundle beside the executable when relocating it.

Install the CLI from the shared `cinemore/homebrew-tap`:

```sh
brew install cinemore/tap/fsr-metal
fsr-metal --self-test
```

The Homebrew formula installs the executable and bundle together in libexec and exposes a wrapper in bin. Its test performs GPU inference, so it also checks resource lookup.

## Validation and release governance

```sh
swift test
swift build -c release --product fsr-metal
.build/release/fsr-metal --self-test
bun tools/release.ts v0.1.0
```

`tools/release.ts` builds both CPU architectures, creates the universal executable, runs the native and universal CLIs **outside the build tree**, and writes archives, SHA256 files, a manifest and binary Homebrew formulas to `dist/v0.1.0/`. It refuses to overwrite a staging directory. The production formula uses GitHub asset URLs; `local/Formula/` uses the same actual archives via file URLs for local Homebrew verification. No placeholder checksums are used.

CI runs package tests, release CLI GPU smoke and an iOS library build. Tag a validated version `vX.Y.Z` to trigger release publication. Optional repository secret `HOMEBREW_TAP_TOKEN` must have write access to `cinemore/homebrew-tap`; the workflow then adds/updates its formula and pushes a narrowly scoped tap commit. Without it, release assets still include the installable formula.

Tests cover real GPU kernels, source/retained output ownership, SDR admission, image conversion, metadata, and EASU-only/RCAS modes and invalid dimensions. Platform declarations are not a claim of device runtime validation; record actual verification in [VALIDATION.md](VALIDATION.md).

## License

MIT. See [LICENSE](LICENSE) and [THIRD-PARTY.md](THIRD-PARTY.md). Upstream shader copyrights and model revision remain with the package.
