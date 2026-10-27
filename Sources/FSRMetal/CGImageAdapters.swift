import CoreGraphics
import CoreVideo
import Foundation

public extension FSRUpscaler {
    /// CGImage入口将输入转换为sRGB BGRA；需要视频颜色元数据时使用CVPixelBuffer入口。
    func enhance(image: CGImage) throws -> CGImage {
        let input = try PixelBufferContext.buffer(width: image.width, height: image.height)
        guard CVPixelBufferLockBaseAddress(input, []) == kCVReturnSuccess else { throw FSRError.unavailable("Input lock") }
        do {
            defer { CVPixelBufferUnlockBaseAddress(input, []) }
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: CVPixelBufferGetBaseAddress(input), width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(input), space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
                throw FSRError.unavailable("Input image context")
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        CVBufferSetAttachment(input, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(input, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_sRGB, .shouldPropagate)
        let output = try enhance(pixelBuffer: input)
        guard CVPixelBufferLockBaseAddress(output, .readOnly) == kCVReturnSuccess else { throw FSRError.unavailable("Output lock") }
        defer { CVPixelBufferUnlockBaseAddress(output, .readOnly) }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: CVPixelBufferGetBaseAddress(output), width: CVPixelBufferGetWidth(output),
                height: CVPixelBufferGetHeight(output), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(output), space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
              let result = context.makeImage() else { throw FSRError.unavailable("Output image context") }
        return result
    }
}
