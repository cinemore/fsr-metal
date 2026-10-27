# Validation record

Verified on 2026-10-27, Apple Silicon MacBook Pro / macOS 27.0.1 / Apple Swift 6.4 (Xcode 27 toolchain).

- `swift test`: **7 passed, 0 failed**. Real GPU kernels, independent retained outputs, unchanged source, HDR rejection, clean-aperture/color attachments, CGImage input, VideoToolbox NV12 conversion, and EASU-only/RCAS parameters and dimension admission.
- `xcodebuild -scheme FSRMetal -destination 'generic/platform=iOS' -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO build`: passed.
- Release builds for arm64 and x86_64: passed. Universal binary contains both slices (lipo verified).
- Native and universal staged binaries outside the build tree: `--version` and real GPU `--self-test` passed.
- Image CLI: 80×45 PNG input -> 160×90 PNG output; three-run benchmark passed. Invalid CLI arguments are rejected with exit 64.
- Binary Homebrew formula: installed the actual checksummed archive through a temporary local tap; `brew test` executed GPU inference successfully.
- Library integrations compiled for macOS and iOS/tvOS/visionOS Simulator targets. The iOS integration included the bundled Metal resources.

Boundaries: Intel macOS binary is built but is not a native Intel GPU runtime test. iOS/tvOS/visionOS builds do not establish device runtime or long-playback coverage.
