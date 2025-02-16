import AVFoundation
import Foundation
import Metal

/// 相机代理协议
public protocol CameraDelegate {
    /// 当捕获到新的视频帧时调用
    /// - Parameter sampleBuffer: 捕获的视频帧
    func didCaptureBuffer(_ sampleBuffer: CMSampleBuffer)
}

/// 物理相机位置枚举
public enum PhysicalCameraLocation {
    case backFacing  // 后置摄像头
    case frontFacing // 前置摄像头

    /// 获取相机位置对应的图像方向
    /// - Returns: 图像方向
    func imageOrientation() -> ImageOrientation {
        switch self {
        case .backFacing: return .landscapeRight
        #if os(iOS)
            case .frontFacing: return .landscapeLeft
        #else
            case .frontFacing: return .portrait
        #endif
        }
    }

    /// 获取相机位置对应的AVCaptureDevice位置
    /// - Returns: AVCaptureDevice位置
    func captureDevicePosition() -> AVCaptureDevice.Position {
        switch self {
        case .backFacing: return .back
        case .frontFacing: return .front
        }
    }

    /// 获取对应位置的AVCaptureDevice实例
    /// - Returns: AVCaptureDevice实例
    func device() -> AVCaptureDevice? {
        let devices = AVCaptureDevice.devices(for: AVMediaType.video)
        for case let device in devices {
            if device.position == self.captureDevicePosition() {
                return device
            }
        }

        return AVCaptureDevice.default(for: AVMediaType.video)
    }
}

/// 相机错误结构体
public struct CameraError: Error {
}

let initialBenchmarkFramesToIgnore = 5

/// 相机类，负责视频捕获和帧处理
public class Camera: NSObject, ImageSource, AVCaptureVideoDataOutputSampleBufferDelegate {

    /// 相机位置
    public var location: PhysicalCameraLocation {
        didSet {
            // TODO: 需要实现相机位置切换逻辑
        }
    }
    
    /// 是否运行性能测试
    public var runBenchmark: Bool = false
    
    /// 是否记录FPS
    public var logFPS: Bool = false

    /// 目标容器
    public let targets = TargetContainer()
    
    /// 相机代理
    public var delegate: CameraDelegate?
    
    /// AVCaptureSession实例
    public let captureSession: AVCaptureSession
    
    /// 图像方向
    public var orientation: ImageOrientation?
    
    /// 输入相机设备
    public let inputCamera: AVCaptureDevice!
    
    /// 视频输入
    let videoInput: AVCaptureDeviceInput!
    
    /// 视频输出
    let videoOutput: AVCaptureVideoDataOutput!
    
    /// Metal纹理缓存
    var videoTextureCache: CVMetalTextureCache?

    /// 是否支持完整YUV范围
    var supportsFullYUVRange: Bool = false
    
    /// 是否以YUV格式捕获
    let captureAsYUV: Bool
    
    /// YUV转换渲染管线状态
    let yuvConversionRenderPipelineState: MTLRenderPipelineState?
    
    /// YUV查找表
    var yuvLookupTable: [String: (Int, MTLStructMember)] = [:]
    
    /// YUV缓冲区大小
    var yuvBufferSize: Int = 0

    /// 帧渲染信号量
    let frameRenderingSemaphore = DispatchSemaphore(value: 1)
    
    /// 相机处理队列
    let cameraProcessingQueue = DispatchQueue.global()
    
    /// 相机帧处理队列
    let cameraFrameProcessingQueue = DispatchQueue(
        label: "com.sunsetlakesoftware.GPUImage.cameraFrameProcessingQueue",
        attributes: [])

    /// 忽略的初始帧数
    let framesToIgnore = 5
    
    /// 已捕获的帧数
    var numberOfFramesCaptured = 0
    
    /// 总帧处理时间
    var totalFrameTimeDuringCapture: Double = 0.0
    
    /// 自上次检查以来的帧数
    var framesSinceLastCheck = 0
    
    /// 上次检查时间
    var lastCheckTime = CFAbsoluteTimeGetCurrent()

    /// 初始化相机
    /// - Parameters:
    ///   - sessionPreset: AVCaptureSession预设
    ///   - cameraDevice: 相机设备（可选）
    ///   - location: 相机位置，默认为后置摄像头
    ///   - orientation: 图像方向（可选）
    ///   - captureAsYUV: 是否以YUV格式捕获，默认为true
    /// - Throws: 初始化失败时抛出错误
    public init(
        sessionPreset: AVCaptureSession.Preset, cameraDevice: AVCaptureDevice? = nil,
        location: PhysicalCameraLocation = .backFacing, orientation: ImageOrientation? = nil,
        captureAsYUV: Bool = true
    ) throws {
        self.location = location
        self.orientation = orientation

        self.captureSession = AVCaptureSession()
        self.captureSession.beginConfiguration()

        self.captureAsYUV = captureAsYUV

        if let cameraDevice = cameraDevice {
            self.inputCamera = cameraDevice
        } else {
            if let device = location.device() {
                self.inputCamera = device
            } else {
                self.videoInput = nil
                self.videoOutput = nil
                self.inputCamera = nil
                self.yuvConversionRenderPipelineState = nil
                super.init()
                throw CameraError()
            }
        }

        do {
            self.videoInput = try AVCaptureDeviceInput(device: inputCamera)
        } catch {
            self.videoInput = nil
            self.videoOutput = nil
            self.yuvConversionRenderPipelineState = nil
            super.init()
            throw error
        }

        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        }

        // 配置视频输出
        videoOutput = AVCaptureVideoDataOutput()
        videoOutput.alwaysDiscardsLateVideoFrames = false

        if captureAsYUV {
            supportsFullYUVRange = false
            let supportedPixelFormats = videoOutput.availableVideoPixelFormatTypes
            for currentPixelFormat in supportedPixelFormats {
                if (currentPixelFormat as NSNumber).int32Value
                    == Int32(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
                {
                    supportsFullYUVRange = true
                }
            }
            if supportsFullYUVRange {
                let (pipelineState, lookupTable, bufferSize) = generateRenderPipelineState(
                    device: sharedMetalRenderingDevice, vertexFunctionName: "twoInputVertex",
                    fragmentFunctionName: "yuvConversionFullRangeFragment",
                    operationName: "YUVToRGB")
                self.yuvConversionRenderPipelineState = pipelineState
                self.yuvLookupTable = lookupTable
                self.yuvBufferSize = bufferSize
                videoOutput.videoSettings = [
                    kCVPixelBufferMetalCompatibilityKey as String: true,
                    kCVPixelBufferPixelFormatTypeKey as String: NSNumber(
                        value: Int32(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)),
                ]
            } else {
                let (pipelineState, lookupTable, bufferSize) = generateRenderPipelineState(
                    device: sharedMetalRenderingDevice, vertexFunctionName: "twoInputVertex",
                    fragmentFunctionName: "yuvConversionVideoRangeFragment",
                    operationName: "YUVToRGB")
                self.yuvConversionRenderPipelineState = pipelineState
                self.yuvLookupTable = lookupTable
                self.yuvBufferSize = bufferSize
                videoOutput.videoSettings = [
                    kCVPixelBufferMetalCompatibilityKey as String: true,
                    kCVPixelBufferPixelFormatTypeKey as String: NSNumber(
                        value: Int32(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)),
                ]
            }
        } else {
            self.yuvConversionRenderPipelineState = nil
            videoOutput.videoSettings = [
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferPixelFormatTypeKey as String: NSNumber(
                    value: Int32(kCVPixelFormatType_32BGRA)),
            ]
        }

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        captureSession.sessionPreset = sessionPreset
        captureSession.commitConfiguration()

        super.init()

        let _ = CVMetalTextureCacheCreate(
            kCFAllocatorDefault, nil, sharedMetalRenderingDevice.device, nil, &videoTextureCache)

        videoOutput.setSampleBufferDelegate(self, queue: cameraProcessingQueue)
    }

    deinit {
        cameraFrameProcessingQueue.sync {
            self.stopCapture()
            self.videoOutput?.setSampleBufferDelegate(nil, queue: nil)
        }
    }

    /// 捕获输出回调
    public func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard
            frameRenderingSemaphore.wait(timeout: DispatchTime.now())
                == DispatchTimeoutResult.success
        else { return }

        let startTime = CFAbsoluteTimeGetCurrent()

        let cameraFrame = CMSampleBufferGetImageBuffer(sampleBuffer)!
        let bufferWidth = CVPixelBufferGetWidth(cameraFrame)
        let bufferHeight = CVPixelBufferGetHeight(cameraFrame)
        let currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        CVPixelBufferLockBaseAddress(
            cameraFrame, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))

        cameraFrameProcessingQueue.async {
            self.delegate?.didCaptureBuffer(sampleBuffer)
            CVPixelBufferUnlockBaseAddress(
                cameraFrame, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))

            let texture: Texture?
            if self.captureAsYUV {
                var luminanceTextureRef: CVMetalTexture? = nil
                var chrominanceTextureRef: CVMetalTexture? = nil
                // 亮度平面
                let _ = CVMetalTextureCacheCreateTextureFromImage(
                    kCFAllocatorDefault, self.videoTextureCache!, cameraFrame, nil, .r8Unorm,
                    bufferWidth, bufferHeight, 0, &luminanceTextureRef)
                // 色度平面
                let _ = CVMetalTextureCacheCreateTextureFromImage(
                    kCFAllocatorDefault, self.videoTextureCache!, cameraFrame, nil, .rg8Unorm,
                    bufferWidth / 2, bufferHeight / 2, 1, &chrominanceTextureRef)

                if let concreteLuminanceTextureRef = luminanceTextureRef,
                    let concreteChrominanceTextureRef = chrominanceTextureRef,
                    let luminanceTexture = CVMetalTextureGetTexture(concreteLuminanceTextureRef),
                    let chrominanceTexture = CVMetalTextureGetTexture(concreteChrominanceTextureRef)
                {
                    let conversionMatrix: Matrix3x3
                    if self.supportsFullYUVRange {
                        conversionMatrix = colorConversionMatrix601FullRangeDefault
                    } else {
                        conversionMatrix = colorConversionMatrix601Default
                    }

                    let outputWidth: Int
                    let outputHeight: Int
                    if (self.orientation ?? self.location.imageOrientation()).rotationNeeded(
                        for: .portrait
                    ).flipsDimensions() {
                        outputWidth = bufferHeight
                        outputHeight = bufferWidth
                    } else {
                        outputWidth = bufferWidth
                        outputHeight = bufferHeight
                    }
                    let outputTexture = Texture(
                        device: sharedMetalRenderingDevice.device, orientation: .portrait,
                        width: outputWidth, height: outputHeight,
                        timingStyle: .videoFrame(timestamp: Timestamp(currentTime)))

                    convertYUVToRGB(
                        pipelineState: self.yuvConversionRenderPipelineState!,
                        lookupTable: self.yuvLookupTable, bufferSize: self.yuvBufferSize,
                        luminanceTexture: Texture(
                            orientation: self.orientation ?? self.location.imageOrientation(),
                            texture: luminanceTexture),
                        chrominanceTexture: Texture(
                            orientation: self.orientation ?? self.location.imageOrientation(),
                            texture: chrominanceTexture),
                        resultTexture: outputTexture, colorConversionMatrix: conversionMatrix)
                    texture = outputTexture
                } else {
                    texture = nil
                }
            } else {
                var textureRef: CVMetalTexture? = nil
                let _ = CVMetalTextureCacheCreateTextureFromImage(
                    kCFAllocatorDefault, self.videoTextureCache!, cameraFrame, nil, .bgra8Unorm,
                    bufferWidth, bufferHeight, 0, &textureRef)
                if let concreteTexture = textureRef,
                    let cameraTexture = CVMetalTextureGetTexture(concreteTexture)
                {
                    texture = Texture(
                        orientation: self.orientation ?? self.location.imageOrientation(),
                        texture: cameraTexture,
                        timingStyle: .videoFrame(timestamp: Timestamp(currentTime)))
                } else {
                    texture = nil
                }
            }

            if texture != nil {
                self.updateTargetsWithTexture(texture!)
            }

            if self.runBenchmark {
                self.numberOfFramesCaptured += 1
                if self.numberOfFramesCaptured > initialBenchmarkFramesToIgnore {
                    let currentFrameTime = (CFAbsoluteTimeGetCurrent() - startTime)
                    self.totalFrameTimeDuringCapture += currentFrameTime
                    print(
                        "Average frame time : \(1000.0 * self.totalFrameTimeDuringCapture / Double(self.numberOfFramesCaptured - initialBenchmarkFramesToIgnore)) ms"
                    )
                    print("Current frame time : \(1000.0 * currentFrameTime) ms")
                }
            }

            if self.logFPS {
                if (CFAbsoluteTimeGetCurrent() - self.lastCheckTime) > 1.0 {
                    self.lastCheckTime = CFAbsoluteTimeGetCurrent()
                    print("FPS: \(self.framesSinceLastCheck)")
                    self.framesSinceLastCheck = 0
                }

                self.framesSinceLastCheck += 1
            }

            self.frameRenderingSemaphore.signal()
        }
    }

    /// 开始捕获
    public func startCapture() {
        let _ = frameRenderingSemaphore.wait(timeout: DispatchTime.distantFuture)
        self.numberOfFramesCaptured = 0
        self.totalFrameTimeDuringCapture = 0
        self.frameRenderingSemaphore.signal()

        if !captureSession.isRunning {
            captureSession.startRunning()
        }
    }

    /// 停止捕获
    public func stopCapture() {
        if captureSession.isRunning {
            let _ = frameRenderingSemaphore.wait(timeout: DispatchTime.distantFuture)

            captureSession.stopRunning()
            self.frameRenderingSemaphore.signal()
        }
    }

    /// 传输上一帧图像
    public func transmitPreviousImage(to target: ImageConsumer, atIndex: UInt) {
        // 相机不需要实现此方法
    }
}
