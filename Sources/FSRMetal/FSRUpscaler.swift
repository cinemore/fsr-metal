import CoreVideo
import Foundation
import Metal

/// 同步入口在内部串行处理并等待GPU完成，每次返回独立的输出缓冲。
public final class FSRUpscaler: @unchecked Sendable {
    private let lock = NSLock()
    private let context: PixelBufferContext
    private let engine: FSREngine
    public let outputWidth: Int
    public let outputHeight: Int
    public let sharpness: Float?

    /// sharpness为nil时只执行EASU；0最强、2最弱。
    public init(outputWidth: Int, outputHeight: Int, sharpness: Float? = 1, device: (any MTLDevice)? = nil) throws {
        guard outputWidth > 0, outputHeight > 0, outputWidth <= 16384, outputHeight <= 16384,
              sharpness.map({ $0.isFinite && (0...2).contains($0) }) ?? true else {
            throw FSRError.invalidInput("Invalid output size or RCAS sharpness")
        }
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
        self.sharpness = sharpness
        context = try PixelBufferContext(device: device)
        engine = try FSREngine(device: context.device)
    }

    public func enhance(pixelBuffer: CVPixelBuffer) throws -> CVPixelBuffer {
        try lock.withLock {
            try context.process(pixelBuffer, width: outputWidth, height: outputHeight) { command, input, output in
                try engine.encode(command: command, input: input, output: output, sharpness: sharpness)
            }
        }
    }
}
