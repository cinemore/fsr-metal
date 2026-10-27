import CoreMedia
import CoreVideo
import Foundation
import Metal
import VideoToolbox

/// 仅由高层处理器在锁内使用；底层engine不接管调用方的队列和输出所有权。
final class PixelBufferContext {
    let device: any MTLDevice
    private let queue: any MTLCommandQueue
    private let cache: CVMetalTextureCache
    private var transfer: VTPixelTransferSession?

    init(device: (any MTLDevice)?) throws {
        guard let device = device ?? MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw FSRError.unavailable("Metal device or command queue")
        }
        self.device = device
        self.queue = queue
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) == kCVReturnSuccess, let cache else {
            throw FSRError.unavailable("Metal texture cache")
        }
        self.cache = cache
    }

    deinit {
        if let transfer { VTPixelTransferSessionInvalidate(transfer) }
    }

    static func validateSDR(_ source: CVPixelBuffer) throws {
        let transfer = CVBufferCopyAttachment(source, kCVImageBufferTransferFunctionKey, nil) as? String
        guard transfer != kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String,
              transfer != kCVImageBufferTransferFunction_ITU_R_2100_HLG as String,
              [kCVImageBufferMasteringDisplayColorVolumeKey, kCVImageBufferContentLightLevelInfoKey, "DolbyVisionRPUData" as CFString]
                .allSatisfy({ CVBufferCopyAttachment(source, $0, nil) == nil }) else {
            throw FSRError.invalidInput("SDR input required")
        }
    }

    func process(
        _ source: CVPixelBuffer, width: Int, height: Int,
        encode: (any MTLCommandBuffer, any MTLTexture, any MTLTexture) throws -> Void
    ) throws -> CVPixelBuffer {
        try Self.validateSDR(source)
        guard width > 0, height > 0, width <= 16384, height <= 16384 else {
            throw FSRError.invalidInput("Output dimensions must be in 1...16384")
        }
        defer { CVMetalTextureCacheFlush(cache, 0) }
        let input: CVPixelBuffer
        if CVPixelBufferGetPixelFormatType(source) == kCVPixelFormatType_32BGRA {
            input = source
        } else {
            if transfer == nil {
                guard VTPixelTransferSessionCreate(allocator: nil, pixelTransferSessionOut: &transfer) == noErr else {
                    throw FSRError.unavailable("Pixel transfer session")
                }
            }
            input = try Self.buffer(width: CVPixelBufferGetWidth(source), height: CVPixelBufferGetHeight(source))
            guard let transfer, VTPixelTransferSessionTransferImage(transfer, from: source, to: input) == noErr else {
                throw FSRError.invalidInput("Unsupported pixel buffer conversion")
            }
        }
        let output = try Self.buffer(width: width, height: height)
        for key in [kCVImageBufferColorPrimariesKey, kCVImageBufferTransferFunctionKey, kCVImageBufferGammaLevelKey,
                    kCVImageBufferCGColorSpaceKey, kCVImageBufferPixelAspectRatioKey] {
            if let value = CVBufferCopyAttachment(source, key, nil) {
                CVBufferSetAttachment(output, key, value, .shouldPropagate)
            }
        }
        CVBufferSetAttachment(output, kCMFormatDescriptionExtension_FullRangeVideo, kCFBooleanTrue, .shouldPropagate)
        CVBufferSetAttachment(output, kCVImageBufferFieldCountKey, NSNumber(value: 1), .shouldPropagate)
        if let aperture = CVBufferCopyAttachment(source, kCVImageBufferCleanApertureKey, nil) as? [String: Any] {
            let sx = Double(width) / Double(CVPixelBufferGetWidth(source))
            let sy = Double(height) / Double(CVPixelBufferGetHeight(source))
            var scaled: [String: Double] = [:]
            for (key, scale) in [(kCVImageBufferCleanApertureWidthKey, sx), (kCVImageBufferCleanApertureHeightKey, sy),
                                 (kCVImageBufferCleanApertureHorizontalOffsetKey, sx), (kCVImageBufferCleanApertureVerticalOffsetKey, sy)] {
                guard let value = aperture[key as String] as? NSNumber, value.doubleValue.isFinite else {
                    throw FSRError.invalidInput("Invalid clean aperture")
                }
                scaled[key as String] = value.doubleValue * scale
            }
            guard scaled[kCVImageBufferCleanApertureWidthKey as String, default: 0] > 0,
                  scaled[kCVImageBufferCleanApertureHeightKey as String, default: 0] > 0 else {
                throw FSRError.invalidInput("Empty clean aperture")
            }
            CVBufferSetAttachment(output, kCVImageBufferCleanApertureKey, scaled as CFDictionary, .shouldPropagate)
        }
        let sourceSurface = try surface(input), destination = try surface(output)
        guard let command = queue.makeCommandBuffer() else { throw FSRError.unavailable("Command buffer") }
        try encode(command, sourceSurface.texture, destination.texture)
        command.commit()
        command.waitUntilCompleted()
        withExtendedLifetime((input, sourceSurface.reference, destination.reference)) {}
        guard command.status == .completed else { throw FSRError.unavailable(command.error?.localizedDescription ?? "GPU completion") }
        return output
    }

    static func buffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var result: CVPixelBuffer?
        let attributes: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:],
                                       kCVPixelBufferMetalCompatibilityKey as String: true]
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &result) == kCVReturnSuccess,
              let result else { throw FSRError.unavailable("Pixel buffer allocation") }
        return result
    }

    private func surface(_ buffer: CVPixelBuffer) throws -> (texture: any MTLTexture, reference: CVMetalTexture) {
        var reference: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(nil, cache, buffer, nil, .bgra8Unorm,
            CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer), 0, &reference) == kCVReturnSuccess,
              let reference, let texture = CVMetalTextureGetTexture(reference) else {
            throw FSRError.unavailable("BGRA Metal mapping")
        }
        return (texture, reference)
    }
}
