import FSRMetal
import ArgumentParser
import CoreGraphics
import Foundation
import ImageIO

@main
struct FSRMetalCLI: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "fsr-metal",
        abstract: "Native Apple Metal FSR 1 EASU/RCAS image enhancement.", version: "0.1.0")

    @Option(name: [.short, .long], help: "Input image path.") var input: String?
    @Option(name: [.short, .long], help: "Output PNG path.") var output: String?
    @Option(name: .long, help: "Repeat enhancement N times after warmup and report milliseconds.") var bench: Int = 0
    @Flag(name: .long, help: "Run a synthetic image through the bundled GPU kernels.") var selfTest = false
    @Option(name: .long, help: "Output width (provide with --height; defaults to 2x).") var width: Int?
    @Option(name: .long, help: "Output height (provide with --width; defaults to 2x).") var height: Int?
    @Option(name: .long, help: "RCAS sharpness: 0 strongest, 2 weakest.") var sharpness: Float = 1
    @Flag(name: .long, help: "Use EASU without RCAS sharpening.") var noSharpen = false

    mutating func validate() throws {
        guard bench >= 0 else { throw ValidationError("--bench must be nonnegative") }
        guard selfTest || (input != nil && output != nil) else { throw ValidationError("Provide --input and --output, or --self-test") }
        guard (width == nil) == (height == nil), width.map({ $0 > 0 && $0 <= 16384 }) ?? true,
              height.map({ $0 > 0 && $0 <= 16384 }) ?? true, sharpness.isFinite && (0...2).contains(sharpness) else {
            throw ValidationError("Provide valid --width and --height together and --sharpness in 0...2")
        }
    }

    func run() throws {
        let image: CGImage
        if selfTest {
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: nil, width: 16, height: 12, bitsPerComponent: 8, bytesPerRow: 64,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let generated = context.makeImage() else { throw ValidationError("Could not create self-test image") }
            image = generated
        } else {
            guard let input, let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: input) as CFURL, nil),
                  let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ValidationError("Could not read input image") }
            image = decoded
        }
        let upscaler = try FSRUpscaler(outputWidth: width ?? image.width * 2, outputHeight: height ?? image.height * 2, sharpness: noSharpen ? nil : sharpness)
        let enhanced = try upscaler.enhance(image: image)
        if selfTest {
            guard enhanced.width == width ?? 32, enhanced.height == height ?? 24 else { throw ValidationError("Self-test output dimensions") }
            print("FSRMetal self-test: 16x12 -> \(enhanced.width)x\(enhanced.height)")
        } else if let output {
            guard let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL, "public.png" as CFString, 1, nil) else {
                throw ValidationError("Could not create output PNG")
            }
            CGImageDestinationAddImage(destination, enhanced, nil)
            guard CGImageDestinationFinalize(destination) else { throw ValidationError("Could not write output PNG") }
        }
        if bench > 0 {
            var samples: [Double] = []
            for _ in 0..<bench {
                let start = DispatchTime.now().uptimeNanoseconds
                _ = try autoreleasepool { try upscaler.enhance(image: image) }
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            }
            print(String(format: "[bench] N=%d mean=%.3f ms min=%.3f ms max=%.3f ms", bench,
                         samples.reduce(0, +) / Double(bench), samples.min() ?? 0, samples.max() ?? 0))
        }
    }
}
