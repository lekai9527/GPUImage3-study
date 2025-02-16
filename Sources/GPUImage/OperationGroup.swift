/// 操作组类，用于组合多个图像处理操作
open class OperationGroup: ImageProcessingOperation {
    /// 输入图像中继
    let inputImageRelay = ImageRelay()
    
    /// 输出图像中继
    let outputImageRelay = ImageRelay()

    /// 源容器，返回输入中继的源容器
    public var sources: SourceContainer { return inputImageRelay.sources }
    
    /// 目标容器，返回输出中继的目标容器
    public var targets: TargetContainer { return outputImageRelay.targets }
    
    /// 最大输入数量，固定为1
    public let maximumInputs: UInt = 1

    /// 初始化操作组
    public init() {
    }

    /// 当新纹理可用时调用
    /// - Parameters:
    ///   - texture: 新纹理
    ///   - fromSourceIndex: 来源索引
    public func newTextureAvailable(_ texture: Texture, fromSourceIndex: UInt) {
        inputImageRelay.newTextureAvailable(texture, fromSourceIndex: fromSourceIndex)
    }

    /// 配置操作组
    /// - Parameter configurationOperation: 配置闭包，接收输入和输出中继
    public func configureGroup(
        _ configurationOperation: (_ input: ImageRelay, _ output: ImageRelay) -> Void
    ) {
        configurationOperation(inputImageRelay, outputImageRelay)
    }

    /// 传输上一帧图像
    /// - Parameters:
    ///   - target: 目标消费者
    ///   - atIndex: 目标索引
    public func transmitPreviousImage(to target: ImageConsumer, atIndex: UInt) {
        outputImageRelay.transmitPreviousImage(to: target, atIndex: atIndex)
    }
}
