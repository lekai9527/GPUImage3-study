import Foundation
import Metal

#if os(iOS)
    import UIKit
#else
    import QuartzCore
#endif

// 定义纹理的时间样式枚举
public enum TextureTimingStyle {
    // 静态图像
    case stillImage
    // 视频帧，带有时间戳
    case videoFrame(timestamp: Timestamp)

    // 判断纹理是否是瞬态的（即是否是视频帧）
    func isTransient() -> Bool {
        switch self {
        case .stillImage: return false
        case .videoFrame: return true
        }
    }

    // 获取时间戳，如果是静态图像则返回 nil
    var timestamp: Timestamp? {
        switch self {
        case .stillImage: return nil
        case let .videoFrame(timestamp): return timestamp
        }
    }
}

// 定义纹理类
public class Texture {
    // 纹理的时间样式
    public var timingStyle: TextureTimingStyle
    // 纹理的方向
    public var orientation: ImageOrientation

    // Metal 纹理对象
    public let texture: MTLTexture

    // 初始化方法，使用现有的 MTLTexture
    public init(
        orientation: ImageOrientation, texture: MTLTexture,
        timingStyle: TextureTimingStyle = .stillImage
    ) {
        self.orientation = orientation
        self.texture = texture
        self.timingStyle = timingStyle
    }

    // 初始化方法，创建新的 MTLTexture
    public init(
        device: MTLDevice, orientation: ImageOrientation, pixelFormat: MTLPixelFormat = .bgra8Unorm,
        width: Int, height: Int, mipmapped: Bool = false,
        timingStyle: TextureTimingStyle = .stillImage
    ) {
        // 创建纹理描述符
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false)
        textureDescriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]

        // 创建纹理对象
        guard
            let newTexture = sharedMetalRenderingDevice.device.makeTexture(
                descriptor: textureDescriptor)
        else {
            fatalError("Could not create texture of size: (\(width), \(height))")
        }

        self.orientation = orientation
        self.texture = newTexture
        self.timingStyle = timingStyle
    }
}

// 扩展 Texture 类，添加纹理坐标计算方法
extension Texture {
    // 根据输出方向和是否归一化计算纹理坐标
    func textureCoordinates(for outputOrientation: ImageOrientation, normalized: Bool) -> [Float] {
        // 计算输入方向需要的旋转
        let inputRotation = self.orientation.rotationNeeded(for: outputOrientation)

        // 根据是否归一化设置坐标限制
        let xLimit: Float
        let yLimit: Float
        if normalized {
            xLimit = 1.0
            yLimit = 1.0
        } else {
            xLimit = Float(self.texture.width)
            yLimit = Float(self.texture.height)
        }

        // 根据旋转方向返回相应的纹理坐标
        switch inputRotation {
        case .noRotation: return [0.0, 0.0, xLimit, 0.0, 0.0, yLimit, xLimit, yLimit]
        case .rotateCounterclockwise: return [0.0, yLimit, 0.0, 0.0, xLimit, yLimit, xLimit, 0.0]
        case .rotateClockwise: return [xLimit, 0.0, xLimit, yLimit, 0.0, 0.0, 0.0, yLimit]
        case .rotate180: return [xLimit, yLimit, 0.0, yLimit, xLimit, 0.0, 0.0, 0.0]
        case .flipHorizontally: return [xLimit, 0.0, 0.0, 0.0, xLimit, yLimit, 0.0, yLimit]
        case .flipVertically: return [0.0, yLimit, xLimit, yLimit, 0.0, 0.0, xLimit, 0.0]
        case .rotateClockwiseAndFlipVertically:
            return [0.0, 0.0, 0.0, yLimit, xLimit, 0.0, xLimit, yLimit]
        case .rotateClockwiseAndFlipHorizontally:
            return [xLimit, yLimit, xLimit, 0.0, 0.0, yLimit, 0.0, 0.0]
        }
    }

    // 根据旋转方向计算纹理的宽高比
    func aspectRatio(for rotation: Rotation) -> Float {
        // TODO: Figure out why my logic was failing on this
        return Float(self.texture.height) / Float(self.texture.width)
        //        if rotation.flipsDimensions() {
        //            return Float(self.texture.width) / Float(self.texture.height)
        //        } else {
        //            return Float(self.texture.height) / Float(self.texture.width)
        //        }
    }

    //    func croppedTextureCoordinates(offsetFromOrigin:Position, cropSize:Size) -> [Float] {
    //        let minX = offsetFromOrigin.x
    //        let minY = offsetFromOrigin.y
    //        let maxX = offsetFromOrigin.x + cropSize.width
    //        let maxY = offsetFromOrigin.y + cropSize.height
    //
    //        switch self {
    //        case .noRotation: return [minX, minY, maxX, minY, minX, maxY, maxX, maxY]
    //        case .rotateCounterclockwise: return [minX, maxY, minX, minY, maxX, maxY, maxX, minY]
    //        case .rotateClockwise: return [maxX, minY, maxX, maxY, minX, minY, minX, maxY]
    //        case .rotate180: return [maxX, maxY, minX, maxY, maxX, minY, minX, minY]
    //        case .flipHorizontally: return [maxX, minY, minX, minY, maxX, maxY, minX, maxY]
    //        case .flipVertically: return [minX, maxY, maxX, maxY, minX, minY, maxX, minY]
    //        case .rotateClockwiseAndFlipVertically: return [minX, minY, minX, maxY, maxX, minY, maxX, maxY]
    //        case .rotateClockwiseAndFlipHorizontally: return [maxX, maxY, maxX, minY, minX, maxY, minX, minY]
    //        }
    //    }
}

// 扩展 Texture 类，添加生成 CGImage 的方法
extension Texture {
    // 将纹理转换为 CGImage
    func cgImage() -> CGImage {
        // 创建命令缓冲区
        guard let commandBuffer = sharedMetalRenderingDevice.commandQueue.makeCommandBuffer() else {
            fatalError("Could not create command buffer on image rendering.")
        }
        // 创建输出纹理
        let outputTexture = Texture(
            device: sharedMetalRenderingDevice.device, orientation: self.orientation,
            width: self.texture.width, height: self.texture.height)
        // 渲染四边形
        commandBuffer.renderQuad(
            pipelineState: sharedMetalRenderingDevice.colorSwizzleRenderState, uniformSettings: nil,
            inputTextures: [0: self], useNormalizedTextureCoordinates: true,
            outputTexture: outputTexture)
        // 提交命令缓冲区
        commandBuffer.commit()
        // 等待命令缓冲区完成
        commandBuffer.waitUntilCompleted()

        // 获取纹理字节数据
        let imageByteSize = texture.height * texture.width * 4
        let outputBytes = UnsafeMutablePointer<UInt8>.allocate(capacity: imageByteSize)
        outputTexture.texture.getBytes(
            outputBytes, bytesPerRow: MemoryLayout<UInt8>.size * texture.width * 4,
            bytesPerImage: 0, from: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0, slice: 0)

        // 创建 CGDataProvider
        guard
            let dataProvider = CGDataProvider(
                dataInfo: nil, data: outputBytes, size: imageByteSize,
                releaseData: dataProviderReleaseCallback)
        else { fatalError("Could not create CGDataProvider") }
        // 创建颜色空间
        let defaultRGBColorSpace = CGColorSpaceCreateDeviceRGB()
        // 创建 CGImage
        return CGImage(
            width: texture.width, height: texture.height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 4 * texture.width, space: defaultRGBColorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: dataProvider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
}

// 回调函数，用于释放 CGDataProvider 的数据
func dataProviderReleaseCallback(
    _ context: UnsafeMutableRawPointer?, data: UnsafeRawPointer, size: Int
) {
    data.deallocate()
}
