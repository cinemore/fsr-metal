# Agent instructions

- Keep the library independent of CinePlayer and host apps. Public APIs use Metal, CoreVideo and CoreGraphics types.
- Preserve shader math, strict FP32 (-fno-fast-math -ffp-contract=off) compilation and upstream attribution.
- Edit source with built-in editing tools. Use Bun/TypeScript for new automation.
- Engines borrow caller resources: document serial use and GPU completion. Never commit caller command buffers.
- Verify with swift test, release CLI image processing, relocated archive smoke tests and Homebrew install/test.
- Tag releases only after validation. Release automation builds arm64, x86_64 and universal archives and computes tap checksums from actual artifacts.
