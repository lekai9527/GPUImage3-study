import Metal

#if canImport(UIKit)
    import UIKit  // 导入UIKit框架（iOS平台）
    public typealias PlatformImageType = UIImage  // 定义平台图像类型为UIImage
#else
    import Cocoa  // 导入Cocoa框架（macOS平台）
    public typealias PlatformImageType = NSImage  // 定义平台图像类型为NSImage
#endif

public enum PictureFileFormat {  // 图片文件格式枚举
    case png  // PNG格式
    case jpeg  // JPEG格式
}

public class PictureOutput: ImageConsumer {  // PictureOutput类，继承自ImageConsumer，用于处理图片输出
    public var encodedImageAvailableCallback: ((Data) -> Void)?  // 编码图像可用时的回调
    public var encodedImageFormat: PictureFileFormat = .png  // 编码图像格式，默认为PNG
    public var imageAvailableCallback: ((PlatformImageType) -> Void)?  // 图像可用时的回调
    public var onlyCaptureNextFrame: Bool = true  // 是否只捕获下一帧
    public var keepImageAroundForSynchronousCapture: Bool = false  // 是否保留图像用于同步捕获
    var storedTexture: Texture?  // 存储的纹理

    public let sources = SourceContainer()  // 源容器
    public let maximumInputs: UInt = 1  // 最大输入数量
    var url: URL!  // 文件保存路径

    public init() {  // 初始化方法
    }

    deinit {  // 析构方法
    }

    public func saveNextFrameToURL(_ url: URL, format: PictureFileFormat) {  // 保存下一帧到指定URL
        onlyCaptureNextFrame = true  // 只捕获下一帧
        encodedImageFormat = format  // 设置编码格式
        self.url = url  // 保存路径
        // Create an intentional short-term retain cycle to prevent deallocation
        // before next frame is captured.
        encodedImageAvailableCallback = { imageData in  // 设置编码图像可用回调
            do {
                try imageData.write(to: self.url, options: .atomic)  // 将图像数据写入文件
            } catch {
                // TODO: Handle this better
                print("WARNING: Couldn't save image with error:\(error)")  // 错误处理
            }
        }
    }

    public func newTextureAvailable(_ texture: Texture, fromSourceIndex: UInt) {  // 新纹理可用时的处理
        if keepImageAroundForSynchronousCapture {  // 如果需要保留图像用于同步捕获
            //            storedTexture?.unlock()
            storedTexture = texture  // 存储纹理
        }

        if let imageCallback = imageAvailableCallback {  // 如果有图像可用回调
            let cgImageFromBytes = texture.cgImage()  // 从纹理生成CGImage

            // TODO: Let people specify orientations
            #if canImport(UIKit)
                let image = UIImage(cgImage: cgImageFromBytes, scale: 1.0, orientation: .up)  // 生成UIImage
            #else
                let image = NSImage(cgImage: cgImageFromBytes, size: NSZeroSize)  // 生成NSImage
            #endif

            imageCallback(image)  // 执行回调

            if onlyCaptureNextFrame {  // 如果只捕获下一帧
                imageAvailableCallback = nil  // 清空回调
            }
        }

        if let imageCallback = encodedImageAvailableCallback {  // 如果有编码图像可用回调
            let cgImageFromBytes = texture.cgImage()  // 从纹理生成CGImage

            let imageData: Data
            #if canImport(UIKit)
                let image = UIImage(cgImage: cgImageFromBytes, scale: 1.0, orientation: .up)  // 生成UIImage
                switch encodedImageFormat {  // 根据编码格式处理
                case .png:
                    // TODO: Better error handling here.
                    imageData = image.pngData()!  // 生成PNG数据
                case .jpeg:
                    // TODO: Be able to set image quality.
                    imageData = image.jpegData(compressionQuality: 0.8)!  // 生成JPEG数据
                }
            #else
                let bitmapRepresentation = NSBitmapImageRep(cgImage: cgImageFromBytes)  // 生成位图表示
                switch encodedImageFormat {  // 根据编码格式处理
                case .png:
                    imageData = bitmapRepresentation.representation(
                        using: .png, properties: [NSBitmapImageRep.PropertyKey(rawValue: ""): ""])!  // 生成PNG数据
                case .jpeg:
                    imageData = bitmapRepresentation.representation(
                        using: .jpeg, properties: [NSBitmapImageRep.PropertyKey(rawValue: ""): ""])!  // 生成JPEG数据
                }
            #endif
            imageCallback(imageData)  // 执行回调

            if onlyCaptureNextFrame {  // 如果只捕获下一帧
                encodedImageAvailableCallback = nil  // 清空回调
            }
        }
    }

    //    public func synchronousImageCapture() -> UIImage {
    //        var outputImage:UIImage!
    //        sharedImageProcessingContext.runOperationSynchronously{
    //            guard let currentFramebuffer = storedFramebuffer else { fatalError("Synchronous access requires keepImageAroundForSynchronousCapture to be set to true") }
    //
    //            let cgImageFromBytes = cgImageFromFramebuffer(currentFramebuffer)
    //            outputImage = UIImage(cgImage:cgImageFromBytes, scale:1.0, orientation:.up)
    //        }
    //
    //        return outputImage
    //    }
}

extension ImageSource {  // ImageSource扩展
    public func saveNextFrameToURL(_ url: URL, format: PictureFileFormat) {  // 保存下一帧到指定URL
        let pictureOutput = PictureOutput()  // 创建PictureOutput实例
        pictureOutput.saveNextFrameToURL(url, format: format)  // 调用保存方法
        self --> pictureOutput  // 连接图像源到输出
    }
}

extension PlatformImageType {  // PlatformImageType扩展
    public func filterWithOperation<T: ImageProcessingOperation>(_ operation: T)
        -> PlatformImageType  // 使用指定操作过滤图像
    {
        return filterWithPipeline { input, output in  // 调用管道过滤方法
            input --> operation --> output  // 连接输入、操作和输出
        }
    }

    public func filterWithPipeline(_ pipeline: (PictureInput, PictureOutput) -> Void)
        -> PlatformImageType  // 使用管道过滤图像
    {
        let picture = PictureInput(image: self)  // 创建PictureInput实例
        var outputImage: PlatformImageType?  // 输出图像
        let pictureOutput = PictureOutput()  // 创建PictureOutput实例
        pictureOutput.onlyCaptureNextFrame = true  // 只捕获下一帧
        pictureOutput.imageAvailableCallback = { image in  // 设置图像可用回调
            outputImage = image  // 保存输出图像
        }
        pipeline(picture, pictureOutput)  // 执行管道
        picture.processImage(synchronously: true)  // 同步处理图像
        return outputImage!  // 返回输出图像
    }
}
