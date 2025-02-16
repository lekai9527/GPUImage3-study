import AVFoundation
import Metal

/// 视频输入类，用于从视频文件读取帧并进行处理
public class MovieInput: ImageSource {
    /// 目标容器，用于管理图像消费者
    public let targets = TargetContainer()
    
    /// 是否运行性能基准测试
    public var runBenchmark = false

    /// Metal纹理缓存，用于存储视频帧
    var videoTextureCache: CVMetalTextureCache?
    
    /// YUV到RGB转换的渲染管线状态
    let yuvConversionRenderPipelineState: MTLRenderPipelineState
    
    /// YUV转换的查找表
    var yuvLookupTable: [String: (Int, MTLStructMember)] = [:]
    
    /// YUV缓冲区大小
    var yuvBufferSize: Int = 0

    /// 视频资源对象
    let asset: AVAsset
    
    /// 视频读取器
    let assetReader: AVAssetReader
    
    /// 是否以实际速度播放
    let playAtActualSpeed: Bool
    
    /// 是否循环播放
    let loop: Bool
    
    /// 视频编码是否完成
    var videoEncodingIsFinished = false
    
    /// 上一帧的时间
    var previousFrameTime = CMTime.zero
    
    /// 上一帧的实际时间
    var previousActualFrameTime = CFAbsoluteTimeGetCurrent()

    /// 捕获的帧数
    var numberOfFramesCaptured = 0
    
    /// 捕获期间的总帧时间
    var totalFrameTimeDuringCapture: Double = 0.0

    // TODO: Add movie reader synchronization
    // TODO: Someone will have to add back in the AVPlayerItem logic, because I don't know how that works
    
    /// 初始化视频输入
    /// - Parameters:
    ///   - asset: 视频资源
    ///   - playAtActualSpeed: 是否以实际速度播放
    ///   - loop: 是否循环播放
    public init(asset: AVAsset, playAtActualSpeed: Bool = false, loop: Bool = false) throws {
        self.asset = asset
        self.playAtActualSpeed = playAtActualSpeed
        self.loop = loop
        
        // 生成YUV到RGB转换的渲染管线
        let (pipelineState, lookupTable, bufferSize) = generateRenderPipelineState(
            device: sharedMetalRenderingDevice, vertexFunctionName: "twoInputVertex",
            fragmentFunctionName: "yuvConversionFullRangeFragment", operationName: "YUVToRGB")
        self.yuvConversionRenderPipelineState = pipelineState
        self.yuvLookupTable = lookupTable
        self.yuvBufferSize = bufferSize
        
        // 创建Metal纹理缓存
        let _ = CVMetalTextureCacheCreate(
            kCFAllocatorDefault, nil, sharedMetalRenderingDevice.device, nil, &videoTextureCache)

        // 初始化视频读取器
        assetReader = try AVAssetReader(asset: self.asset)

        // 设置视频输出参数
        let outputSettings: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            (kCVPixelBufferPixelFormatTypeKey as String): NSNumber(
                value: Int32(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)),
        ]
        
        // 创建视频轨道输出
        let readerVideoTrackOutput = AVAssetReaderTrackOutput(
            track: self.asset.tracks(withMediaType: AVMediaType.video)[0],
            outputSettings: outputSettings)
        readerVideoTrackOutput.alwaysCopiesSampleData = false
        assetReader.add(readerVideoTrackOutput)
        // TODO: Audio here
    }

    public convenience init(url: URL, playAtActualSpeed: Bool = false, loop: Bool = false) throws {
        let inputOptions = [AVURLAssetPreferPreciseDurationAndTimingKey: NSNumber(value: true)]
        let inputAsset = AVURLAsset(url: url, options: inputOptions)
        try self.init(asset: inputAsset, playAtActualSpeed: playAtActualSpeed, loop: loop)
    }

    // MARK: -
    // MARK: Playback control

    public func start() {
        asset.loadValuesAsynchronously(
            forKeys: ["tracks"],
            completionHandler: {
                DispatchQueue.global().async(execute: {
                    guard self.asset.statusOfValue(forKey: "tracks", error: nil) == .loaded else {
                        return
                    }

                    guard self.assetReader.startReading() else {
                        print("Couldn't start reading")
                        return
                    }

                    var readerVideoTrackOutput: AVAssetReaderOutput? = nil

                    for output in self.assetReader.outputs {
                        if output.mediaType == AVMediaType.video {
                            readerVideoTrackOutput = output
                        }
                    }

                    while self.assetReader.status == .reading {
                        self.readNextVideoFrame(from: readerVideoTrackOutput!)
                    }

                    if self.assetReader.status == .completed {
                        self.assetReader.cancelReading()

                        if self.loop {
                            // TODO: Restart movie processing
                        } else {
                            self.endProcessing()
                        }
                    }
                })
            })
    }

    public func cancel() {
        assetReader.cancelReading()
        self.endProcessing()
    }

    func endProcessing() {

    }

    // MARK: -
    // MARK: Internal processing functions

    func readNextVideoFrame(from videoTrackOutput: AVAssetReaderOutput) {
        if (assetReader.status == .reading) && !videoEncodingIsFinished {
            if let sampleBuffer = videoTrackOutput.copyNextSampleBuffer() {
                if playAtActualSpeed {
                    // Do this outside of the video processing queue to not slow that down while waiting
                    let currentSampleTime = CMSampleBufferGetOutputPresentationTimeStamp(
                        sampleBuffer)
                    let differenceFromLastFrame = CMTimeSubtract(
                        currentSampleTime, previousFrameTime)
                    let currentActualTime = CFAbsoluteTimeGetCurrent()

                    let frameTimeDifference = CMTimeGetSeconds(differenceFromLastFrame)
                    let actualTimeDifference = currentActualTime - previousActualFrameTime

                    if frameTimeDifference > actualTimeDifference {
                        usleep(
                            UInt32(round(1000000.0 * (frameTimeDifference - actualTimeDifference))))
                    }

                    previousFrameTime = currentSampleTime
                    previousActualFrameTime = CFAbsoluteTimeGetCurrent()
                }

                //                sharedImageProcessingContext.runOperationSynchronously{
                self.process(movieFrame: sampleBuffer)
                CMSampleBufferInvalidate(sampleBuffer)
                //                }
            } else {
                if !loop {
                    videoEncodingIsFinished = true
                    if videoEncodingIsFinished {
                        self.endProcessing()
                    }
                }
            }
        }
        //        else if (synchronizedMovieWriter != nil) {
        //            if (assetReader.status == .Completed) {
        //                self.endProcessing()
        //            }
        //        }

    }

    func process(movieFrame frame: CMSampleBuffer) {
        let currentSampleTime = CMSampleBufferGetOutputPresentationTimeStamp(frame)
        let movieFrame = CMSampleBufferGetImageBuffer(frame)!

        //        processingFrameTime = currentSampleTime
        self.process(movieFrame: movieFrame, withSampleTime: currentSampleTime)
    }

    func process(movieFrame: CVPixelBuffer, withSampleTime: CMTime) {
        let bufferHeight = CVPixelBufferGetHeight(movieFrame)
        let bufferWidth = CVPixelBufferGetWidth(movieFrame)
        CVPixelBufferLockBaseAddress(movieFrame, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))

        let conversionMatrix = colorConversionMatrix601FullRangeDefault
        // TODO: Get this color query working
        //        if let colorAttachments = CVBufferGetAttachment(movieFrame, kCVImageBufferYCbCrMatrixKey, nil) {
        //            if(CFStringCompare(colorAttachments, kCVImageBufferYCbCrMatrix_ITU_R_601_4, 0) == .EqualTo) {
        //                _preferredConversion = kColorConversion601FullRange
        //            } else {
        //                _preferredConversion = kColorConversion709
        //            }
        //        } else {
        //            _preferredConversion = kColorConversion601FullRange
        //        }

        let startTime = CFAbsoluteTimeGetCurrent()

        let texture: Texture?
        var luminanceTextureRef: CVMetalTexture? = nil
        var chrominanceTextureRef: CVMetalTexture? = nil
        // Luminance plane
        let _ = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, self.videoTextureCache!, movieFrame, nil, .r8Unorm, bufferWidth,
            bufferHeight, 0, &luminanceTextureRef)
        // Chrominance plane
        let _ = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, self.videoTextureCache!, movieFrame, nil, .rg8Unorm,
            bufferWidth / 2, bufferHeight / 2, 1, &chrominanceTextureRef)

        if let concreteLuminanceTextureRef = luminanceTextureRef,
            let concreteChrominanceTextureRef = chrominanceTextureRef,
            let luminanceTexture = CVMetalTextureGetTexture(concreteLuminanceTextureRef),
            let chrominanceTexture = CVMetalTextureGetTexture(concreteChrominanceTextureRef)
        {
            let outputTexture = Texture(
                device: sharedMetalRenderingDevice.device, orientation: .portrait,
                width: bufferWidth, height: bufferHeight,
                timingStyle: .videoFrame(timestamp: Timestamp(withSampleTime)))

            convertYUVToRGB(
                pipelineState: self.yuvConversionRenderPipelineState,
                lookupTable: self.yuvLookupTable, bufferSize: self.yuvBufferSize,
                luminanceTexture: Texture(orientation: .portrait, texture: luminanceTexture),
                chrominanceTexture: Texture(orientation: .portrait, texture: chrominanceTexture),
                resultTexture: outputTexture, colorConversionMatrix: conversionMatrix)
            texture = outputTexture
        } else {
            texture = nil
        }

        CVPixelBufferUnlockBaseAddress(
            movieFrame, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))

        if texture != nil {
            self.updateTargetsWithTexture(texture!)
        }

        if self.runBenchmark {
            let currentFrameTime = (CFAbsoluteTimeGetCurrent() - startTime)
            self.numberOfFramesCaptured += 1
            self.totalFrameTimeDuringCapture += currentFrameTime
            print(
                "Average frame time : \(1000.0 * self.totalFrameTimeDuringCapture / Double(self.numberOfFramesCaptured)) ms"
            )
            print("Current frame time : \(1000.0 * currentFrameTime) ms")
        }
    }

    public func transmitPreviousImage(to target: ImageConsumer, atIndex: UInt) {
        // Not needed for movie inputs
    }
}

extension Timestamp {
    public init(_ time: CMTime) {
        self.value = time.value
        self.timescale = time.timescale
        self.flags = TimestampFlags(rawValue: time.flags.rawValue)
        self.epoch = time.epoch
    }

    public var asCMTime: CMTime {
        return CMTimeMakeWithEpoch(value: value, timescale: timescale, epoch: epoch)
    }
}
