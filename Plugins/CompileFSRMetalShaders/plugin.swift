import Foundation
import PackagePlugin

@main
struct CompileFSRMetalShaders: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard target is SourceModuleTarget else { return [] }
        let shader = target.directory.appending("Shaders/FSRKernels.metal")
        let air = context.pluginWorkDirectory.appending("FSR.air")
        let library = context.pluginWorkDirectory.appending("default.metallib")
        let cache = context.pluginWorkDirectory.appending("MetalModuleCache")
        return [
            .buildCommand(displayName: "Compile FSR Metal kernels", executable: Path("/usr/bin/xcrun"),
                arguments: ["metal", "-c", "-fno-fast-math", "-ffp-contract=off", "-fmodules-cache-path=\(cache.string)", shader.string, "-o", air.string],
                inputFiles: [shader], outputFiles: [air]),
            .buildCommand(displayName: "Link FSR default.metallib", executable: Path("/usr/bin/xcrun"),
                arguments: ["metallib", air.string, "-o", library.string], inputFiles: [air], outputFiles: [library])
        ]
    }
}
