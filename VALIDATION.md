# Validation record

Verified on 2026-10-27, Apple Silicon MacBook Pro / macOS 27.0.1 / Apple Swift 6.4 (Xcode 27 toolchain).

- `swift test`: **7 passed, 0 failed**. Real GPU kernels, independent retained outputs, unchanged source, HDR rejection, clean-aperture/color attachments, CGImage input, VideoToolbox NV12 conversion, and EASU-only/RCAS parameters and dimension admission.
- `xcodebuild -scheme FSRMetal -destination 'generic/platform=iOS' -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO build`: passed.
- Release builds for arm64 and x86_64: passed. Universal binary contains both slices (lipo verified).
- Native and universal staged binaries outside the build tree: `--version` and real GPU `--self-test` passed.
- Image CLI: 80×45 PNG input -> 160×90 PNG output; three-run benchmark passed. Invalid CLI arguments are rejected with exit 64.
- Binary Homebrew formula: installed the actual checksummed archive through a temporary local tap; `brew test` executed GPU inference successfully.
- Cinemore integration builds passed for macOS, iOS Simulator, tvOS Simulator and visionOS Simulator. Resource bundles were present in the iOS app.
- Cinemore's existing frozen full-frame output SHA256 remained `467b11c1864fc07bf15af195d26245a3f72b571f7fa7f78c4c5eed015cb721c9`. Existing A/B split hashes also matched.
- Final isolated macOS formal playback: FSR ordinary and A/B both delivered **191/191 enhanced frames** in the existing steady window, exact independent PTS/duration timeline, no callback timeout/bypass or player error, zero measured steady lateness, and drained work after shutdown.

The first mixed integration run had two timing failures across the two engines; it was retained. The four-engine-mode isolated replay passed unchanged assertions and the original 40ms budget. The host record is `cinemore-apple/docs/dev-flow/fsr-artcnn-packages-20261027.md`; raw evidence and xcresult remain in that worktree's ignored `.build/` directory.

Boundaries: Intel macOS binary is built but is not a native Intel GPU runtime test. iOS/tvOS/visionOS builds do not establish device runtime or long-playback coverage. Existing VT-only host tests were skipped on this Mac. GitHub release publication and a public Homebrew tap update are separate from these local validation results.
