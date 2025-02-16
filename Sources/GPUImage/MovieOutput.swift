import AVFoundation

// 定义音频编码目标协议
public protocol AudioEncodingTarget {
    // 激活音频轨道
    func activateAudioTrack()
    // 处理音频缓冲区
    func processAudioBuffer(_ sampleBuffer: CMSampleBuffer)
}

// 视频输出类，实现 ImageConsumer 和 AudioEncodingTarget 协议
public class MovieOutput: ImageConsumer, AudioEncodingTarget {
    // 输入源容器
    public let sources = SourceContainer()
    // 最大输入数量
    public let maximumInputs: UInt = 1

    // 资产写入器
    let assetWriter: AVAssetWriter
    // 视频输入
    let assetWriterVideoInput: AVAssetWriterInput
    // 音频输入（可选）
    var assetWriterAudioInput: AVAssetWriterInput?

    // 像素缓冲区输入适配器
    let assetWriterPixelBufferInput: AVAssetWriterInputPixelBufferAdaptor
    // 视频大小
    let size: Size
    // 是否正在录制
    private var isRecording = false
    // 视频编码是否完成
    private var videoEncodingIsFinished = false
    // 音频编码是否完成
    private var audioEncodingIsFinished = false
    // 开始时间
    private var startTime: CMTime?
    // 上一帧时间
    private var previousFrameTime = CMTime.negativeInfinity
    // 上一音频时间
    private var previousAudioTime = CMTime.negativeInfinity
    // 是否编码实时视频
    private var encodingLiveVideo: Bool
    // 像素缓冲区
    var pixelBuffer: CVPixelBuffer? = nil

    // 渲染管道状态
    var renderPipelineState: MTLRenderPipelineState!

    // 视频变换
    public var transform: CGAffineTransform {
        get {
            return assetWriterVideoInput.transform
        }
        set {
            assetWriterVideoInput.transform = newValue
        }
    }

    // 初始化方法
    public init(
        URL: Foundation.URL, size: Size, fileType: AVFileType = AVFileType.mov,
        liveVideo: Bool = false, settings: [String: AnyObject]? = nil
    ) throws {
        self.size = size
        // 创建资产写入器
        assetWriter = try AVAssetWriter(url: URL, fileType: fileType)
        // 设置电影片段间隔，确保即使录制中断也能生成有效的电影文件
        assetWriter.movieFragmentInterval = CMTimeMakeWithSeconds(1.0, preferredTimescale: 1000)

        var localSettings: [String: AnyObject]
        if let settings = settings {
            localSettings = settings
        } else {
            localSettings = [String: AnyObject]()
        }

        // 设置视频宽度和高度
        localSettings[AVVideoWidthKey] =
            localSettings[AVVideoWidthKey] ?? NSNumber(value: size.width)
        localSettings[AVVideoHeightKey] =
            localSettings[AVVideoHeightKey] ?? NSNumber(value: size.height)
        // 设置视频编解码器
        localSettings[AVVideoCodecKey] =
            localSettings[AVVideoCodecKey] ?? AVVideoCodecH264 as NSString

        // 创建视频输入
        assetWriterVideoInput = AVAssetWriterInput(
            mediaType: AVMediaType.video, outputSettings: localSettings)
        assetWriterVideoInput.expectsMediaDataInRealTime = liveVideo
        encodingLiveVideo = liveVideo

        // 设置像素缓冲区属性
        let sourcePixelBufferAttributesDictionary: [String: AnyObject] = [
            kCVPixelBufferPixelFormatTypeKey as String: NSNumber(
                value: Int32(kCVPixelFormatType_32BGRA)),
            kCVPixelBufferWidthKey as String: NSNumber(value: size.width),
            kCVPixelBufferHeightKey as String: NSNumber(value: size.height),
        ]

        // 创建像素缓冲区输入适配器
        assetWriterPixelBufferInput = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: assetWriterVideoInput,
            sourcePixelBufferAttributes: sourcePixelBufferAttributesDictionary)
        assetWriter.add(assetWriterVideoInput)

        // 生成渲染管道状态
        let (pipelineState, _, _) = generateRenderPipelineState(
            device: sharedMetalRenderingDevice, vertexFunctionName: "oneInputVertex",
            fragmentFunctionName: "passthroughFragment", operationName: "RenderView")
        self.renderPipelineState = pipelineState
    }

    // 开始录制
    public func startRecording(transform: CGAffineTransform? = nil) {
        if let transform = transform {
            assetWriterVideoInput.transform = transform
        }
        startTime = nil
        self.isRecording = self.assetWriter.startWriting()
    }

    // 结束录制
    public func finishRecording(_ completionCallback: (() -> Void)? = nil) {
        self.isRecording = false

        // 检查资产写入器状态
        if self.assetWriter.status == .completed || self.assetWriter.status == .cancelled
            || self.assetWriter.status == .unknown
        {
            DispatchQueue.global().async {
                completionCallback?()
            }
            return
        }
        if (self.assetWriter.status == .writing) && (!self.videoEncodingIsFinished) {
            self.videoEncodingIsFinished = true
            self.assetWriterVideoInput.markAsFinished()
        }
        if (self.assetWriter.status == .writing) && (!self.audioEncodingIsFinished) {
            self.audioEncodingIsFinished = true
            self.assetWriterAudioInput?.markAsFinished()
        }

        // 完成写入
        if let callback = completionCallback {
            self.assetWriter.finishWriting(completionHandler: callback)
        } else {
            self.assetWriter.finishWriting {}
        }
    }

    // 新纹理可用时调用
    public func newTextureAvailable(_ texture: Texture, fromSourceIndex: UInt) {
        guard isRecording else { return }
        // 忽略静态图像和其他非视频更新
        guard let frameTime = texture.timingStyle.timestamp?.asCMTime else { return }
        // 避免添加相同时间戳的帧
        guard frameTime != previousFrameTime else { return }

        if startTime == nil {
            if assetWriter.status != .writing {
                assetWriter.startWriting()
            }

            assetWriter.startSession(atSourceTime: frameTime)
            startTime = frameTime
        }

        // 检查视频输入是否准备好接收更多媒体数据
        guard assetWriterVideoInput.isReadyForMoreMediaData || (!encodingLiveVideo) else {
            debugPrint("Had to drop a frame at time \(frameTime)")
            return
        }

        var pixelBufferFromPool: CVPixelBuffer? = nil

        // 从像素缓冲区池中获取像素缓冲区
        let pixelBufferStatus = CVPixelBufferPoolCreatePixelBuffer(
            nil, assetWriterPixelBufferInput.pixelBufferPool!, &pixelBufferFromPool)
        guard let pixelBuffer = pixelBufferFromPool, pixelBufferStatus == kCVReturnSuccess else {
            return
        }

        // 锁定像素缓冲区基地址
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        renderIntoPixelBuffer(pixelBuffer, texture: texture)

        // 将像素缓冲区追加到资产写入器
        if !assetWriterPixelBufferInput.append(pixelBuffer, withPresentationTime: frameTime) {
            print("Problem appending pixel buffer at time: \(frameTime)")
        }

        // 解锁像素缓冲区基地址
        CVPixelBufferUnlockBaseAddress(
            pixelBuffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
    }

    // 将纹理渲染到像素缓冲区
    func renderIntoPixelBuffer(_ pixelBuffer: CVPixelBuffer, texture: Texture) {
        guard let pixelBufferBytes = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            print("Could not get buffer bytes")
            return
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        let outputTexture: Texture
        // 检查纹理大小是否匹配
        if (Int(round(self.size.width)) != texture.texture.width)
            && (Int(round(self.size.height)) != texture.texture.height)
        {
            let commandBuffer = sharedMetalRenderingDevice.commandQueue.makeCommandBuffer()

            // 创建输出纹理
            outputTexture = Texture(
                device: sharedMetalRenderingDevice.device, orientation: .portrait,
                width: Int(round(self.size.width)), height: Int(round(self.size.height)),
                timingStyle: texture.timingStyle)

            // 渲染四边形到输出纹理
            commandBuffer?.renderQuad(
                pipelineState: renderPipelineState, inputTextures: [0: texture],
                outputTexture: outputTexture)
            commandBuffer?.commit()
            commandBuffer?.waitUntilCompleted()
        } else {
            outputTexture = texture
        }

        // 定义区域
        let region = MTLRegionMake2D(
            0, 0, outputTexture.texture.width, outputTexture.texture.height)

        // 从输出纹理获取字节数据并写入像素缓冲区
        outputTexture.texture.getBytes(
            pixelBufferBytes, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
    }

    // MARK: -
    // MARK: 音频支持

    // 激活音频轨道
    public func activateAudioTrack() {
        // TODO: Add ability to set custom output settings
        assetWriterAudioInput = AVAssetWriterInput(
            mediaType: AVMediaType.audio, outputSettings: nil)
        assetWriter.add(assetWriterAudioInput!)
        assetWriterAudioInput?.expectsMediaDataInRealTime = encodingLiveVideo
    }

    // 处理音频缓冲区
    public func processAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let assetWriterAudioInput = assetWriterAudioInput else { return }

        let currentSampleTime = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer)
        if self.startTime == nil {
            if self.assetWriter.status != .writing {
                self.assetWriter.startWriting()
            }

            self.assetWriter.startSession(atSourceTime: currentSampleTime)
            self.startTime = currentSampleTime
        }

        // 检查音频输入是否准备好接收更多媒体数据
        guard assetWriterAudioInput.isReadyForMoreMediaData || (!self.encodingLiveVideo) else {
            return
        }

        // 将音频样本缓冲区追加到资产写入器
        if !assetWriterAudioInput.append(sampleBuffer) {
            print("Trouble appending audio sample buffer")
        }
    }
}
