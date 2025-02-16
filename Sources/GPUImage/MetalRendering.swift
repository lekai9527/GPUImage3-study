import Foundation
import Metal

// OpenGL uses a bottom-left origin while Metal uses a top-left origin.
/// 标准图像顶点坐标，用于渲染四边形
public let standardImageVertices: [Float] = [-1.0, 1.0, 1.0, 1.0, -1.0, -1.0, 1.0, -1.0]

extension MTLCommandBuffer {
    /// 使用指定颜色清除纹理
    /// - Parameters:
    ///   - color: 清除颜色
    ///   - outputTexture: 目标纹理
    func clear(with color: Color, outputTexture: Texture) {
        // 创建渲染通道描述符
        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = outputTexture.texture
        renderPass.colorAttachments[0].clearColor = MTLClearColorMake(
            Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent),
            Double(color.alphaComponent))
        renderPass.colorAttachments[0].storeAction = .store
        renderPass.colorAttachments[0].loadAction = .clear

        print("Clear color: \(renderPass.colorAttachments[0].clearColor)")

        // 创建渲染编码器
        guard let renderEncoder = self.makeRenderCommandEncoder(descriptor: renderPass) else {
            fatalError("Could not create render encoder")
        }
        //        renderEncoder.setRenderPipelineState(sharedMetalRenderingDevice.passthroughRenderState)

        //        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 0)

        renderEncoder.endEncoding()
    }

    /// 渲染四边形
    /// - Parameters:
    ///   - pipelineState: 渲染管线状态
    ///   - uniformSettings: 着色器统一设置
    ///   - inputTextures: 输入纹理字典
    ///   - useNormalizedTextureCoordinates: 是否使用归一化纹理坐标
    ///   - imageVertices: 图像顶点坐标
    ///   - outputTexture: 输出纹理
    ///   - outputOrientation: 输出方向
    func renderQuad(
        pipelineState: MTLRenderPipelineState, uniformSettings: ShaderUniformSettings? = nil,
        inputTextures: [UInt: Texture], useNormalizedTextureCoordinates: Bool = true,
        imageVertices: [Float] = standardImageVertices, outputTexture: Texture,
        outputOrientation: ImageOrientation = .portrait
    ) {
        // 创建顶点缓冲区
        let vertexBuffer = sharedMetalRenderingDevice.device.makeBuffer(
            bytes: imageVertices,
            length: imageVertices.count * MemoryLayout<Float>.size,
            options: [])!
        vertexBuffer.label = "Vertices"

        // 配置渲染通道
        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = outputTexture.texture
        renderPass.colorAttachments[0].clearColor = MTLClearColorMake(1, 0, 0, 1)
        renderPass.colorAttachments[0].storeAction = .store
        renderPass.colorAttachments[0].loadAction = .clear

        // 创建渲染编码器
        guard let renderEncoder = self.makeRenderCommandEncoder(descriptor: renderPass) else {
            fatalError("Could not create render encoder")
        }
        renderEncoder.setFrontFacing(.counterClockwise)
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        // 处理每个输入纹理
        for textureIndex in 0..<inputTextures.count {
            let currentTexture = inputTextures[UInt(textureIndex)]!

            // 获取纹理坐标并创建缓冲区
            let inputTextureCoordinates = currentTexture.textureCoordinates(
                for: outputOrientation, normalized: useNormalizedTextureCoordinates)
            let textureBuffer = sharedMetalRenderingDevice.device.makeBuffer(
                bytes: inputTextureCoordinates,
                length: inputTextureCoordinates.count * MemoryLayout<Float>.size,
                options: [])!
            textureBuffer.label = "Texture Coordinates"

            // 设置顶点缓冲区和片段纹理
            renderEncoder.setVertexBuffer(textureBuffer, offset: 0, index: 1 + textureIndex)
            renderEncoder.setFragmentTexture(currentTexture.texture, index: textureIndex)
        }
        // 恢复着色器设置并绘制
        uniformSettings?.restoreShaderSettings(renderEncoder: renderEncoder)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
    }
}

/// 生成渲染管线状态
/// - Parameters:
///   - device: Metal渲染设备
///   - vertexFunctionName: 顶点函数名称
///   - fragmentFunctionName: 片段函数名称
///   - operationName: 操作名称
/// - Returns: 包含渲染管线状态、uniform查找表和缓冲区大小的元组
func generateRenderPipelineState(
    device: MetalRenderingDevice, vertexFunctionName: String, fragmentFunctionName: String,
    operationName: String
) -> (MTLRenderPipelineState, [String: (Int, MTLStructMember)], Int) {
    // 获取顶点函数
    guard let vertexFunction = device.shaderLibrary.makeFunction(name: vertexFunctionName) else {
        fatalError("\(operationName): could not compile vertex function \(vertexFunctionName)")
    }

    // 获取片段函数
    guard let fragmentFunction = device.shaderLibrary.makeFunction(name: fragmentFunctionName)
    else {
        fatalError("\(operationName): could not compile fragment function \(fragmentFunctionName)")
    }

    // 创建渲染管线描述符
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.colorAttachments[0].pixelFormat = MTLPixelFormat.bgra8Unorm  // 设置像素格式
    descriptor.rasterSampleCount = 1  // 设置采样数
    descriptor.vertexFunction = vertexFunction  // 设置顶点函数
    descriptor.fragmentFunction = fragmentFunction  // 设置片段函数

    do {
        var reflection: MTLAutoreleasedRenderPipelineReflection?
        // 创建渲染管线状态
        let pipelineState = try device.device.makeRenderPipelineState(
            descriptor: descriptor, options: [.bufferTypeInfo, .argumentInfo],
            reflection: &reflection)

        var uniformLookupTable: [String: (Int, MTLStructMember)] = [:]  // 创建uniform查找表
        var bufferSize: Int = 0  // 初始化缓冲区大小
        // 处理片段参数
        if let fragmentArguments = reflection?.fragmentArguments {
            for fragmentArgument in fragmentArguments where fragmentArgument.type == .buffer {
                if fragmentArgument.bufferDataType == .struct,
                    let members = fragmentArgument.bufferStructType?.members.enumerated()
                {
                    bufferSize = fragmentArgument.bufferDataSize  // 获取缓冲区大小
                    // 遍历成员并填充查找表
                    for (index, uniform) in members {
                        uniformLookupTable[uniform.name] = (index, uniform)
                    }
                }
            }
        }

        return (pipelineState, uniformLookupTable, bufferSize)
    } catch {
        fatalError(
            "Could not create render pipeline state for vertex:\(vertexFunctionName), fragment:\(fragmentFunctionName), error:\(error)"
        )
    }
}
