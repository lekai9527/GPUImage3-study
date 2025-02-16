import MetalKit

#if canImport(UIKit)
    import UIKit  // 导入UIKit框架（iOS平台）
#else
    import Cocoa  // 导入Cocoa框架（macOS平台）
#endif

public class PictureInput: ImageSource {  // PictureInput类，继承自ImageSource，用于处理图片输入
    // 目标容器，用于存储图像处理链中的目标
    public let targets = TargetContainer()  // 目标容器，用于存储图像处理链中的目标
    // 内部纹理，用于存储处理后的图像纹理
    var internalTexture: Texture?  // 内部纹理，用于存储处理后的图像纹理
    // 标记是否已经处理过图像
    var hasProcessedImage: Bool = false  // 标记是否已经处理过图像
    // 内部图像，存储输入的CGImage对象
    var internalImage: CGImage?  // 内部图像，存储输入的CGImage对象

    // 初始化方法，接受CGImage对象
    public init(
        image: CGImage, smoothlyScaleOutput: Bool = false, orientation: ImageOrientation = .portrait
    ) {  // 初始化方法，接受CGImage对象
        internalImage = image
    }

    #if canImport(UIKit)
        // 使用UIImage初始化
        public convenience init(
            image: UIImage, smoothlyScaleOutput: Bool = false,
            orientation: ImageOrientation = .portrait
        ) {  // 便捷初始化方法，接受UIImage对象
            self.init(
                image: image.cgImage!, smoothlyScaleOutput: smoothlyScaleOutput,
                orientation: orientation)
        }

        // 使用图片名称初始化
        public convenience init(
            imageName: String, smoothlyScaleOutput: Bool = false,
            orientation: ImageOrientation = .portrait
        ) {  // 便捷初始化方法，通过图片名称加载UIImage
            guard let image = UIImage(named: imageName) else {
                fatalError("No such image named: \(imageName) in your application bundle")
            }
            self.init(
                image: image, smoothlyScaleOutput: smoothlyScaleOutput, orientation: orientation)
        }
    #else
        // 使用NSImage初始化
        public convenience init(
            image: NSImage, smoothlyScaleOutput: Bool = false,
            orientation: ImageOrientation = .portrait
        ) {  // 便捷初始化方法，接受NSImage对象（macOS平台）
            self.init(
                image: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!,
                smoothlyScaleOutput: smoothlyScaleOutput, orientation: orientation)
        }

        // 使用图片名称初始化
        public convenience init(
            imageName: String, smoothlyScaleOutput: Bool = false,
            orientation: ImageOrientation = .portrait
        ) {  // 便捷初始化方法，通过图片名称加载NSImage（macOS平台）
            let imageName = NSImage.Name(imageName)
            guard let image = NSImage(named: imageName) else {
                fatalError("No such image named: \(imageName) in your application bundle")
            }
            self.init(
                image: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!,
                smoothlyScaleOutput: smoothlyScaleOutput, orientation: orientation)
        }
    #endif

    // 处理图像，可以选择同步或异步处理
    public func processImage(synchronously: Bool = false) {  // 处理图像的核心方法
        if let texture = internalTexture {  // 如果已经存在纹理
            if synchronously {  // 同步处理
                self.updateTargetsWithTexture(texture)
                self.hasProcessedImage = true
            } else {  // 异步处理
                DispatchQueue.global().async {
                    self.updateTargetsWithTexture(texture)
                    self.hasProcessedImage = true
                }
            }
        } else {  // 如果不存在纹理，需要创建新纹理
            let textureLoader = MTKTextureLoader(device: sharedMetalRenderingDevice.device)
            if synchronously {  // 同步加载纹理
                do {
                    let imageTexture = try textureLoader.newTexture(
                        cgImage: internalImage!, options: [MTKTextureLoader.Option.SRGB: false])
                    internalImage = nil
                    self.internalTexture = Texture(orientation: .portrait, texture: imageTexture)
                    self.updateTargetsWithTexture(self.internalTexture!)
                    self.hasProcessedImage = true
                } catch {
                    fatalError("Failed loading image texture")
                }
            } else {  // 异步加载纹理
                textureLoader.newTexture(
                    cgImage: internalImage!, options: [MTKTextureLoader.Option.SRGB: false],
                    completionHandler: { (possibleTexture, error) in
                        guard error == nil else {
                            fatalError("Error in loading texture: \(error!)")
                        }
                        guard let texture = possibleTexture else {
                            fatalError("Nil texture received")
                        }
                        self.internalImage = nil
                        self.internalTexture = Texture(orientation: .portrait, texture: texture)
                        DispatchQueue.global().async {
                            self.updateTargetsWithTexture(self.internalTexture!)
                            self.hasProcessedImage = true
                        }
                    })
            }
        }
    }

    // 将处理过的图像传递给目标消费者
    public func transmitPreviousImage(to target: ImageConsumer, atIndex: UInt) {  // 将处理后的图像传递给目标
        if hasProcessedImage {  // 如果图像已经处理过
            target.newTextureAvailable(self.internalTexture!, fromSourceIndex: atIndex)  // 将纹理传递给目标
        }
    }
}
