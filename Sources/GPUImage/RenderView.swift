import Foundation
import MetalKit

// RenderView类继承自MTKView并实现ImageConsumer协议
// 用于在Metal视图中渲染图像
public class RenderView: MTKView, ImageConsumer {

    public let sources = SourceContainer()  // 图像源容器
    public let maximumInputs: UInt = 1  // 最大输入数量
    var currentTexture: Texture?  // 当前要渲染的纹理
    var renderPipelineState: MTLRenderPipelineState!  // 渲染管线状态

    // 通过frame和device初始化
    public override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: sharedMetalRenderingDevice.device)

        commonInit()  // 调用通用初始化方法
    }

    // 通过NSCoder初始化（用于Storyboard/XIB）
    public required init(coder: NSCoder) {
        super.init(coder: coder)

        commonInit()  // 调用通用初始化方法
    }

    // 通用初始化方法
    private func commonInit() {
        framebufferOnly = false  // 允许读写帧缓冲区
        autoResizeDrawable = true  // 自动调整drawable大小

        self.device = sharedMetalRenderingDevice.device  // 设置Metal设备

        // 生成渲染管线状态
        let (pipelineState, _, _) = generateRenderPipelineState(
            device: sharedMetalRenderingDevice, vertexFunctionName: "oneInputVertex",
            fragmentFunctionName: "passthroughFragment", operationName: "RenderView")
        self.renderPipelineState = pipelineState

        enableSetNeedsDisplay = false  // 禁用自动重绘
        isPaused = true  // 暂停渲染循环
    }

    // 当新纹理可用时调用
    public func newTextureAvailable(_ texture: Texture, fromSourceIndex: UInt) {
        self.drawableSize = CGSize(width: texture.texture.width, height: texture.texture.height)  // 设置drawable大小
        currentTexture = texture  // 更新当前纹理
        self.draw()  // 触发绘制
    }

    // 绘制方法
    public override func draw(_ rect: CGRect) {
        if let currentDrawable = self.currentDrawable, let imageTexture = currentTexture {
            // 创建命令缓冲区
            let commandBuffer = sharedMetalRenderingDevice.commandQueue.makeCommandBuffer()

            // 创建输出纹理
            let outputTexture = Texture(orientation: .portrait, texture: currentDrawable.texture)
            // 渲染四边形
            commandBuffer?.renderQuad(
                pipelineState: renderPipelineState, inputTextures: [0: imageTexture],
                outputTexture: outputTexture)

            commandBuffer?.present(currentDrawable)  // 呈现drawable
            commandBuffer?.commit()  // 提交命令缓冲区
        }
    }
}
