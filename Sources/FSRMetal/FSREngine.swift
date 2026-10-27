import Foundation
import Metal

/// 单实例须串行编码，并在GPU完成后复用工作区；不提交调用方的命令缓冲。
public final class FSREngine {
    private let device: any MTLDevice
    private let easu: any MTLComputePipelineState
    private let rcas: any MTLComputePipelineState
    private var workspace: (any MTLTexture)?

    public init(device: any MTLDevice) throws {
        let library = try device.makeDefaultLibrary(bundle: Bundle.module)
        self.device = device
        guard let easu = library.makeFunction(name: "fsrEasu"), let rcas = library.makeFunction(name: "fsrRcas") else {
            throw FSRError.unavailable("FSR shaders")
        }
        self.easu = try device.makeComputePipelineState(function: easu)
        self.rcas = try device.makeComputePipelineState(function: rcas)
    }

    public func encode(
        command: any MTLCommandBuffer,
        input: any MTLTexture,
        output: any MTLTexture,
        sharpness: Float?
    ) throws {
        guard input !== output, output.width >= input.width, output.height >= input.height,
              output.width > input.width || output.height > input.height,
              input.textureType == .type2D, output.textureType == .type2D,
              input.device.registryID == device.registryID, output.device.registryID == device.registryID,
              command.device.registryID == device.registryID,
              sharpness.map({ $0.isFinite && (0...2).contains($0) }) ?? true
        else { throw FSRError.invalidInput("Expected enlarged 2D textures on the engine device and RCAS sharpness in 0...2") }
        if sharpness != nil, workspace?.width != output.width || workspace?.height != output.height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float,
                                                                      width: output.width, height: output.height, mipmapped: false)
            descriptor.storageMode = .shared
            descriptor.usage = [.shaderRead, .shaderWrite]
            workspace = device.makeTexture(descriptor: descriptor)
        }
        let target: any MTLTexture
        if sharpness != nil {
            guard let workspace else {
                throw FSRError.unavailable("FSR workspace")
            }
            target = workspace
        } else {
            target = output
        }
        let rw = 1 / Float(output.width), rh = 1 / Float(output.height)
        var mapping = SIMD4<Float>(Float(input.width) * rw, Float(input.height) * rh,
                                   0.5 * Float(input.width) * rw - 0.5, 0.5 * Float(input.height) * rh - 0.5)
        guard let encoder = command.makeComputeCommandEncoder() else {
            throw FSRError.unavailable("FSR encoder")
        }
        encoder.setComputePipelineState(easu)
        encoder.setTexture(input, index: 0); encoder.setTexture(target, index: 1)
        encoder.setBytes(&mapping, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        dispatch(encoder, output: target)
        if let sharpness {
            var strength = exp2(-sharpness)
            guard let encoder = command.makeComputeCommandEncoder() else {
                throw FSRError.unavailable("RCAS encoder")
            }
            encoder.setComputePipelineState(rcas)
            encoder.setTexture(target, index: 0); encoder.setTexture(output, index: 1)
            encoder.setBytes(&strength, length: MemoryLayout<Float>.stride, index: 0)
            dispatch(encoder, output: output)
        }
    }

    private func dispatch(_ encoder: any MTLComputeCommandEncoder, output: any MTLTexture) {
        encoder.dispatchThreads(MTLSize(width: output.width, height: output.height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 16, height: 8, depth: 1))
        encoder.endEncoding()
    }
}
