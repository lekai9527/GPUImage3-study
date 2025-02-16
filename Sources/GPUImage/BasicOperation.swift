import Foundation
import Metal

// MARK: - 基础图像处理操作
// 本文件定义了图像处理的基础操作类，负责Metal渲染管线的配置和执行

/// 根据输入数量获取默认顶点函数名
/// - Parameter inputCount: 输入纹理数量
/// - Returns: 对应的顶点函数名称
public func defaultVertexFunctionNameForInputs(_ inputCount: UInt) -> String {
    switch inputCount {
    case 1:
        return "oneInputVertex"
    case 2:
        return "twoInputVertex"
    default:
        return "oneInputVertex"
    }
}

/// 基础图像处理操作类
/// 负责管理Metal渲染管线，处理输入纹理并输出处理结果
open class BasicOperation: ImageProcessingOperation {

    /// 最大输入数量
    public let maximumInputs: UInt
    
    /// 目标容器，存储所有输出目标
    public let targets = TargetContainer()
    
    /// 源容器，存储所有输入源
    public let sources = SourceContainer()

    /// 是否在下一帧激活直通模式
    public var activatePassthroughOnNextFrame: Bool = false
    
    /// 着色器uniform设置
    public var uniformSettings: ShaderUniformSettings
    
    /// 是否使用Metal性能着色器
    /// 注意：如果设备不支持会自动禁用
    public var useMetalPerformanceShaders: Bool = false {
        didSet {
            if !sharedMetalRenderingDevice.metalPerformanceShadersAreSupported {
                print("Warning: Metal Performance Shaders are not supported on this device")
                useMetalPerformanceShaders = false
            }
        }
    }

    /// 渲染管线状态
    let renderPipelineState: MTLRenderPipelineState
    
    /// 操作名称，用于调试和日志
    let operationName: String
    
    /// 输入纹理字典，key为输入索引
    var inputTextures = [UInt: Texture]()
    
    /// 纹理输入信号量，用于线程同步
    let textureInputSemaphore = DispatchSemaphore(value: 1)
    
    /// 是否使用归一化纹理坐标
    var useNormalizedTextureCoordinates = true
    
    /// Metal性能着色器处理路径（可选）
    var metalPerformanceShaderPathway: ((MTLCommandBuffer, [UInt: Texture], Texture) -> Void)?

    /// 初始化基础操作
    /// - Parameters:
    ///   - vertexFunctionName: 顶点函数名（可选

    /// 初始化基础操作
    /// - Parameters:
    ///   - vertexFunctionName: 顶点函数名（可选），默认根据输入数量自动选择
    ///   - fragmentFunctionName: 片段函数名（必需）
    ///   - numberOfInputs: 输入数量，默认为1
    ///   - operationName: 操作名称，默认为文件名
    public init(
        vertexFunctionName: String? = nil, fragmentFunctionName: String, numberOfInputs: UInt = 1,
        operationName: String = #file
    ) {
        self.maximumInputs = numberOfInputs
        self.operationName = operationName

        let concreteVertexFunctionName =
            vertexFunctionName ?? defaultVertexFunctionNameForInputs(numberOfInputs)
        let (pipelineState, lookupTable, bufferSize) = generateRenderPipelineState(
            device: sharedMetalRenderingDevice, vertexFunctionName: concreteVertexFunctionName,
            fragmentFunctionName: fragmentFunctionName, operationName: operationName)
        self.renderPipelineState = pipelineState
        self.uniformSettings = ShaderUniformSettings(
            uniformLookupTable: lookupTable, bufferSize: bufferSize)
    }

    /// 将上一帧图像传输给目标消费者
    /// - Parameters:
    ///   - target: 目标消费者
    ///   - atIndex: 目标索引
    public func transmitPreviousImage(to target: ImageConsumer, atIndex: UInt) {
        // TODO: 待实现
    }

    /// 当新纹理可用时调用
    /// - Parameters:
    ///   - texture: 新纹理
    ///   - fromSourceIndex: 来源索引
    public func newTextureAvailable(_ texture: Texture, fromSourceIndex: UInt) {
        let _ = textureInputSemaphore.wait(timeout: DispatchTime.distantFuture)
        defer {
            textureInputSemaphore.signal()
        }

        inputTextures[fromSourceIndex] = texture

        if (UInt(inputTextures.count) >= maximumInputs) || activatePassthroughOnNextFrame {
            let outputWidth: Int
            let outputHeight: Int

            let firstInputTexture = inputTextures[0]!
            if firstInputTexture.orientation.rotationNeeded(for: .portrait).flipsDimensions() {
                outputWidth = firstInputTexture.texture.height
                outputHeight = firstInputTexture.texture.width
            } else {
                outputWidth = firstInputTexture.texture.width
                outputHeight = firstInputTexture.texture.height
            }

            if uniformSettings.usesAspectRatio {
                let outputRotation = firstInputTexture.orientation.rotationNeeded(for: .portrait)
                uniformSettings["aspectRatio"] = firstInputTexture.aspectRatio(for: outputRotation)
            }

            guard let commandBuffer = sharedMetalRenderingDevice.commandQueue.makeCommandBuffer()
            else { return }

            let outputTexture = Texture(
                device: sharedMetalRenderingDevice.device, orientation: .portrait,
                width: outputWidth, height: outputHeight, timingStyle: firstInputTexture.timingStyle
            )

            guard !activatePassthroughOnNextFrame else {
                // Use this to allow a bootstrap of cyclical processing, like with a low pass filter.
                activatePassthroughOnNextFrame = false
                // TODO: Render rotated passthrough image here

                removeTransientInputs()
                textureInputSemaphore.signal()
                updateTargetsWithTexture(outputTexture)
                let _ = textureInputSemaphore.wait(timeout: DispatchTime.distantFuture)

                return
            }

            if let alternateRenderingFunction = metalPerformanceShaderPathway,
                useMetalPerformanceShaders
            {
                var rotatedInputTextures: [UInt: Texture]
                if firstInputTexture.orientation.rotationNeeded(for: .portrait) != .noRotation {
                    let rotationOutputTexture = Texture(
                        device: sharedMetalRenderingDevice.device, orientation: .portrait,
                        width: outputWidth, height: outputHeight)
                    guard
                        let rotationCommandBuffer = sharedMetalRenderingDevice.commandQueue
                            .makeCommandBuffer()
                    else { return }
                    rotationCommandBuffer.renderQuad(
                        pipelineState: sharedMetalRenderingDevice.passthroughRenderState,
                        uniformSettings: uniformSettings, inputTextures: inputTextures,
                        useNormalizedTextureCoordinates: useNormalizedTextureCoordinates,
                        outputTexture: rotationOutputTexture)
                    rotationCommandBuffer.commit()
                    rotatedInputTextures = inputTextures
                    rotatedInputTextures[0] = rotationOutputTexture
                } else {
                    rotatedInputTextures = inputTextures
                }
                alternateRenderingFunction(commandBuffer, rotatedInputTextures, outputTexture)
            } else {
                internalRenderFunction(commandBuffer: commandBuffer, outputTexture: outputTexture)
            }
            commandBuffer.commit()

            removeTransientInputs()
            textureInputSemaphore.signal()
            updateTargetsWithTexture(outputTexture)
            let _ = textureInputSemaphore.wait(timeout: DispatchTime.distantFuture)
        }
    }

    /// 移除临时输入纹理
    func removeTransientInputs() {
        for index in 0..<self.maximumInputs {
            if let texture = inputTextures[index], texture.timingStyle.isTransient() {
                inputTextures[index] = nil
            }
        }
    }

    /// 内部渲染函数，执行实际的渲染操作
    /// - Parameters:
    ///   - commandBuffer: Metal命令缓冲区
    ///   - outputTexture: 输出纹理
    func internalRenderFunction(commandBuffer: MTLCommandBuffer, outputTexture: Texture) {
        commandBuffer.renderQuad(
            pipelineState: renderPipelineState, uniformSettings: uniformSettings,
            inputTextures: inputTextures,
            useNormalizedTextureCoordinates: useNormalizedTextureCoordinates,
            outputTexture: outputTexture)
    }
}
