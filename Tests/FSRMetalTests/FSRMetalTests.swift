@testable import FSRMetal
import CoreGraphics
import CoreVideo
import Metal
import XCTest

final class FSRMetalTests: XCTestCase {
    private func input(width: Int = 16, height: Int = 12) throws -> CVPixelBuffer {
        let buffer = try PixelBufferContext.buffer(width: width, height: height)
        XCTAssertEqual(CVPixelBufferLockBaseAddress(buffer, []), kCVReturnSuccess)
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let address = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
        for y in 0..<height {
            let row = address.advanced(by: y * CVPixelBufferGetBytesPerRow(buffer)).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                row[x * 4] = UInt8((x * 13 + y * 7) % 256)
                row[x * 4 + 1] = 96
                row[x * 4 + 2] = 180
                row[x * 4 + 3] = 255
            }
        }
        CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        return buffer
    }

    private func bytes(_ buffer: CVPixelBuffer) throws -> [UInt8] {
        XCTAssertEqual(CVPixelBufferLockBaseAddress(buffer, .readOnly), kCVReturnSuccess)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let address = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
        return (0..<CVPixelBufferGetHeight(buffer)).flatMap { y in
            Array(UnsafeBufferPointer(start: address.advanced(by: y * CVPixelBufferGetBytesPerRow(buffer)).assumingMemoryBound(to: UInt8.self),
                                      count: CVPixelBufferGetWidth(buffer) * 4))
        }
    }

    func testBundledKernelsPreserveSourceAndRetainedOutputs() throws {
        let source = try input()
        let before = try bytes(source)
        let upscaler = try FSRUpscaler(outputWidth: 32, outputHeight: 24)
        let first = try upscaler.enhance(pixelBuffer: source)
        let frozen = try bytes(first)
        let second = try upscaler.enhance(pixelBuffer: source)
        XCTAssertFalse(first === second)
        XCTAssertEqual(CVPixelBufferGetWidth(first), 32)
        XCTAssertEqual(CVPixelBufferGetHeight(first), 24)
        XCTAssertEqual(try bytes(source), before)
        XCTAssertEqual(try bytes(first), frozen)
        XCTAssertEqual(try bytes(second), frozen)
        XCTAssertEqual(stride(from: 3, to: frozen.count, by: 4).map { frozen[$0] }, [UInt8](repeating: 255, count: 32 * 24))
    }

    func testRejectsHDRWithoutTouchingInput() throws {
        let source = try input()
        let before = try bytes(source)
        CVBufferSetAttachment(source, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ, .shouldPropagate)
        let upscaler = try FSRUpscaler(outputWidth: 32, outputHeight: 24)
        XCTAssertThrowsError(try upscaler.enhance(pixelBuffer: source))
        XCTAssertEqual(try bytes(source), before)
    }

    func testDisplayApertureScalesWithOutput() throws {
        let source = try input()
        let aperture = [kCVImageBufferCleanApertureWidthKey as String: 14.0, kCVImageBufferCleanApertureHeightKey as String: 10.0,
                        kCVImageBufferCleanApertureHorizontalOffsetKey as String: 0.5, kCVImageBufferCleanApertureVerticalOffsetKey as String: 0.25]
        CVBufferSetAttachment(source, kCVImageBufferCleanApertureKey, aperture as CFDictionary, .shouldPropagate)
        let output = try FSRUpscaler(outputWidth: 32, outputHeight: 24).enhance(pixelBuffer: source)
        let actual = try XCTUnwrap(CVBufferCopyAttachment(output, kCVImageBufferCleanApertureKey, nil) as? [String: Double])
        XCTAssertEqual(actual[kCVImageBufferCleanApertureWidthKey as String], 28)
        XCTAssertEqual(actual[kCVImageBufferCleanApertureHorizontalOffsetKey as String], 1)
        XCTAssertNil(CVBufferCopyAttachment(output, kCVImageBufferYCbCrMatrixKey, nil))
    }

    func testVideoToolboxNV12InputPreservesColorMetadata() throws {
        var buffer: CVPixelBuffer?
        let attributes: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:],
                                       kCVPixelBufferMetalCompatibilityKey as String: true]
        XCTAssertEqual(CVPixelBufferCreate(nil, 16, 12, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                          attributes as CFDictionary, &buffer), kCVReturnSuccess)
        let source = try XCTUnwrap(buffer)
        XCTAssertEqual(CVPixelBufferLockBaseAddress(source, []), kCVReturnSuccess)
        for plane in 0..<CVPixelBufferGetPlaneCount(source) {
            let address = try XCTUnwrap(CVPixelBufferGetBaseAddressOfPlane(source, plane))
            address.initializeMemory(as: UInt8.self, repeating: plane == 0 ? 96 : 128,
                count: CVPixelBufferGetBytesPerRowOfPlane(source, plane) * CVPixelBufferGetHeightOfPlane(source, plane))
        }
        CVPixelBufferUnlockBaseAddress(source, [])
        CVBufferSetAttachment(source, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(source, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(source, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        let output = try FSRUpscaler(outputWidth: 32, outputHeight: 24).enhance(pixelBuffer: source)
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(output), kCVPixelFormatType_32BGRA)
        XCTAssertEqual(CVPixelBufferGetWidth(output), 32)
        XCTAssertEqual(CVPixelBufferGetHeight(output), 24)
        XCTAssertEqual(CVBufferCopyAttachment(output, kCVImageBufferColorPrimariesKey, nil) as? String,
                       kCVImageBufferColorPrimaries_ITU_R_709_2 as String)
        XCTAssertEqual(CVBufferCopyAttachment(output, kCVImageBufferTransferFunctionKey, nil) as? String,
                       kCVImageBufferTransferFunction_ITU_R_709_2 as String)
        XCTAssertNil(CVBufferCopyAttachment(output, kCVImageBufferYCbCrMatrixKey, nil))
        XCTAssertTrue(try bytes(output).contains { $0 > 0 && $0 < 255 })
    }

    func testCGImageEntryPoint() throws {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 6, bitsPerComponent: 8, bytesPerRow: 32,
                                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let enhanced = try FSRUpscaler(outputWidth: 16, outputHeight: 12).enhance(image: image)
        XCTAssertEqual(enhanced.width, 16)
        XCTAssertEqual(enhanced.height, 12)
    }

    func testInvalidConfigurationAndNonEnlargingOutput() throws {
        XCTAssertThrowsError(try FSRUpscaler(outputWidth: 0, outputHeight: 24))
        XCTAssertThrowsError(try FSRUpscaler(outputWidth: 32, outputHeight: 24, sharpness: .nan))
        XCTAssertThrowsError(try FSRUpscaler(outputWidth: 32, outputHeight: 24, sharpness: 3))
        let source = try input()
        XCTAssertThrowsError(try FSRUpscaler(outputWidth: 16, outputHeight: 12).enhance(pixelBuffer: source))
    }

    func testEASUOnlyAndRCASHandleConstantPixels() throws {
        let source = try PixelBufferContext.buffer(width: 8, height: 8)
        CVPixelBufferLockBaseAddress(source, [])
        let address = try XCTUnwrap(CVPixelBufferGetBaseAddress(source))
        for y in 0..<8 {
            let row = address.advanced(by: y * CVPixelBufferGetBytesPerRow(source)).assumingMemoryBound(to: UInt8.self)
            for x in 0..<8 { for channel in 0..<4 { row[x * 4 + channel] = channel == 3 ? 255 : 96 } }
        }
        CVPixelBufferUnlockBaseAddress(source, [])
        for sharpness: Float? in [nil, 0, 1, 2] {
            let output = try FSRUpscaler(outputWidth: 16, outputHeight: 16, sharpness: sharpness).enhance(pixelBuffer: source)
            let actual = try bytes(output)
            for index in actual.indices where index % 4 != 3 { XCTAssertEqual(Int(actual[index]), 96, accuracy: 1) }
        }
    }
}
