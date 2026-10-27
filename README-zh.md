# FSRMetal

[English](README.md) | [简体中文](README-zh.md)

Apple Metal 原生 FSR 1 EASU／RCAS 空间超分，提供独立 Swift Package 和 macOS 命令行程序。库不依赖 CinePlayer、Anime4K 或播放器界面，Metal 资源、模型来源及许可证由包自行管理。

## 使用

通过 `.package(url: "https://github.com/cinemore/fsr-metal.git", exact: "0.1.0")` 引入 `FSRMetal` product；本机开发也可使用 `.package(path: "../fsr-metal")`：

```swift
import FSRMetal
let upscaler = try FSRUpscaler(outputWidth: 3840, outputHeight: 2160, sharpness: 1)
let output = try upscaler.enhance(pixelBuffer: input)
let imageOutput = try upscaler.enhance(image: image)
```

输出必须放大输入，调用方决定目标尺寸和宽高比。锐化参数 nil 关闭 RCAS；0 最强、2 最弱。

高层入口内部串行并等待 GPU 完成，每次返回独立输出，不改写原图或先前结果；支持 BGRA 和 VideoToolbox 可转换的像素缓冲，保留显示／颜色附件并缩放 clean aperture。CGImage 入口转为 sRGB BGRA。仅支持 SDR；拒绝 HDR／杜比元数据。

底层 `FSREngine` 接收调用方的纹理和 command buffer，不代为提交或等待。单实例须串行编码，GPU 完成后才可复用工作区。 播放预算、代际、帧率准入、三槽背压及播放行为由宿主负责。

## 命令行和分发

```sh
swift run fsr-metal --input input.png --output output.png --width 3840 --height 2160 --sharpness 1
swift run fsr-metal --self-test
swift run fsr-metal --input input.png --output output.png --bench 5
```

默认输出 2×；宽高参数须成对传入，--no-sharpen 只执行 EASU。 发布工作流生成 arm64、x86_64、universal 二进制归档，程序与资源 bundle 必须放在相邻位置。通过共享 Homebrew tap 安装：

```sh
brew install cinemore/tap/fsr-metal
fsr-metal --self-test
```

## 验证与治理

```sh
swift test
swift build -c release --product fsr-metal
.build/release/fsr-metal --self-test
bun tools/release.ts v0.1.0
```

发布工具采用 Bun／TypeScript。归档、真实 SHA256、manifest 及 Homebrew 配方位于 dist/v0.1.0/；local/Formula 使用同一归档的本地文件 URL，可独立验证安装。重复 staging 目录会被拒绝，避免覆盖已有结果。

CI 包含包测试、Release CLI 的真实 GPU 自检和 iOS 库构建。验证后推送版本 tag 才触发公开发布。HOMEBREW_TAP_TOKEN 配置为共享 cinemore/homebrew-tap 的写权限后，工作流自动提交本包的配方；未配置时，Release 仍附带配方。完整参数、底层接口所有权及发布流程见 [English README](README.md)，实际设备验证边界见 [VALIDATION.md](VALIDATION.md)。

MIT；上游来源、固定模型 revision 和完整许可见 [THIRD-PARTY.md](THIRD-PARTY.md)。
