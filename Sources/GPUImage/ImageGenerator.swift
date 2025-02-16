/// 图像生成器，用于创建并管理纹理数据
public class ImageGenerator: ImageSource {
    /// 生成图像的尺寸
    public var size: Size

    /// 目标容器，用于管理图像消费者
    public let targets = TargetContainer()
    
    // 内部使用的Metal纹理对象
    var internalTexture: Texture!

    /// 初始化图像生成器
    /// - Parameter size: 生成图像的尺寸
    public init(size: Size) {
        self.size = size
        // 创建新的纹理对象
        internalTexture = Texture(
            device: sharedMetalRenderingDevice.device, orientation: .portrait,
            width: Int(size.width), height: Int(size.height), timingStyle: .stillImage)
    }

    /// 将生成的图像传递给指定的目标
    /// - Parameters:
    ///   - target: 图像消费者
    ///   - atIndex: 目标索引
    public func transmitPreviousImage(to target: ImageConsumer, atIndex: UInt) {
        target.newTextureAvailable(internalTexture, fromSourceIndex: atIndex)
    }

    // 通知所有目标有新纹理可用
    func notifyTargets() {
        updateTargetsWithTexture(internalTexture)
    }
}
