import Foundation
import Metal
import MetalPerformanceShaders

/// 共享的Metal渲染设备实例
public let sharedMetalRenderingDevice = MetalRenderingDevice()

/// Metal渲染设备类，封装了Metal的核心功能
public class MetalRenderingDevice {
    // MTLDevice
    // MTLCommandQueue

    /// Metal设备对象
    public let device: MTLDevice
    
    /// 命令队列，用于提交渲染命令
    public let commandQueue: MTLCommandQueue
    
    /// 着色器库，包含所有可用的着色器函数
    public let shaderLibrary: MTLLibrary
    
    /// 是否支持Metal Performance Shaders
    public let metalPerformanceShadersAreSupported: Bool

    /// 直通渲染管线状态，用于简单的纹理传递
    lazy var passthroughRenderState: MTLRenderPipelineState = {
        let (pipelineState, _, _) = generateRenderPipelineState(
            device: self, vertexFunctionName: "oneInputVertex",
            fragmentFunctionName: "passthroughFragment", operationName: "Passthrough")
        return pipelineState
    }()

    /// 颜色交换渲染管线状态，用于颜色通道的交换
    lazy var colorSwizzleRenderState: MTLRenderPipelineState = {
        let (pipelineState, _, _) = generateRenderPipelineState(
            device: self, vertexFunctionName: "oneInputVertex",
            fragmentFunctionName: "colorSwizzleFragment", operationName: "ColorSwizzle")
        return pipelineState
    }()

    /// 初始化Metal渲染设备
    init() {
        // 创建默认的Metal设备
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Could not create Metal Device")
        }
        self.device = device

        // 创建命令队列
        guard let queue = self.device.makeCommandQueue() else {
            fatalError("Could not create command queue")
        }
        self.commandQueue = queue

        // 检查是否支持Metal Performance Shaders
        if #available(iOS 9, macOS 10.13, *) {
            self.metalPerformanceShadersAreSupported = MPSSupportsMTLDevice(device)
        } else {
            self.metalPerformanceShadersAreSupported = false
        }

        // 加载默认的着色器库
        guard let defaultLibrary = try? device.makeDefaultLibrary(bundle: Bundle.module) else {
            fatalError("Could not load library")
        }

        self.shaderLibrary = defaultLibrary
    }
}
