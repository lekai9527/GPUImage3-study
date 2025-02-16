// MARK: -
// MARK: Basic types
import Foundation

/// 图像源协议，定义图像处理管道的输入源
public protocol ImageSource {
    /// 目标容器，存储所有连接的目标消费者
    var targets: TargetContainer { get }
    
    /// 传输上一帧图像到指定目标
    /// - Parameters:
    ///   - target: 目标消费者
    ///   - atIndex: 目标索引
    func transmitPreviousImage(to target: ImageConsumer, atIndex: UInt)
}

/// 图像消费者协议，定义图像处理管道的输出目标
public protocol ImageConsumer: AnyObject {
    /// 最大输入数量
    var maximumInputs: UInt { get }
    
    /// 源容器，存储所有连接的输入源
    var sources: SourceContainer { get }

    /// 当新纹理可用时调用
    /// - Parameters:
    ///   - texture: 新纹理
    ///   - fromSourceIndex: 来源索引
    func newTextureAvailable(_ texture: Texture, fromSourceIndex: UInt)
}

/// 图像处理操作协议，继承自ImageConsumer和ImageSource
public protocol ImageProcessingOperation: ImageConsumer, ImageSource {
}

infix operator --> : AdditionPrecedence

/// 图像处理操作链式调用操作符
/// - Parameters:
///   - source: 图像源
///   - destination: 图像消费者
/// - Returns: 目标消费者
@discardableResult public func --> <T: ImageConsumer>(source: ImageSource, destination: T) -> T {
    source.addTarget(destination)
    return destination
}

// MARK: -
// MARK: Extensions and supporting types

/// ImageSource协议的扩展实现
extension ImageSource {
    /// 添加目标消费者
    /// - Parameters:
    ///   - target: 目标消费者
    ///   - atTargetIndex: 可选的目标索引
    public func addTarget(_ target: ImageConsumer, atTargetIndex: UInt? = nil) {
        if let targetIndex = atTargetIndex {
            target.setSource(self, atIndex: targetIndex)
            targets.append(target, indexAtTarget: targetIndex)
            transmitPreviousImage(to: target, atIndex: targetIndex)
        } else if let indexAtTarget = target.addSource(self) {
            targets.append(target, indexAtTarget: indexAtTarget)
            transmitPreviousImage(to: target, atIndex: indexAtTarget)
        } else {
            debugPrint("Warning: tried to add target beyond target's input capacity")
        }
    }

    /// 移除所有目标消费者
    public func removeAllTargets() {
        for (target, index) in targets {
            target.removeSourceAtIndex(index)
        }
        targets.removeAll()
    }

    /// 使用新纹理更新所有目标
    /// - Parameter texture: 新纹理
    public func updateTargetsWithTexture(_ texture: Texture) {
        //        if targets.count == 0 { // Deal with the case where no targets are attached by immediately returning framebuffer to cache
        //            framebuffer.lock()
        //            framebuffer.unlock()
        //        } else {
        //            // Lock first for each output, to guarantee proper ordering on multi-output operations
        //            for _ in targets {
        //                framebuffer.lock()
        //            }
        //        }
        for (target, index) in targets {
            target.newTextureAvailable(texture, fromSourceIndex: index)
        }
    }
}

extension ImageConsumer {
    /// 添加图像源
    /// - Parameter source: 图像源
    /// - Returns: 添加的索引
    public func addSource(_ source: ImageSource) -> UInt? {
        return sources.append(source, maximumInputs: maximumInputs)
    }

    /// 设置图像源
    /// - Parameters:
    ///   - source: 图像源
    ///   - atIndex: 目标索引
    public func setSource(_ source: ImageSource, atIndex: UInt) {
        _ = sources.insert(source, atIndex: atIndex, maximumInputs: maximumInputs)
    }

    /// 移除指定索引的图像源
    /// - Parameter index: 要移除的索引
    public func removeSourceAtIndex(_ index: UInt) {
        sources.removeAtIndex(index)
    }
}

/// 弱引用图像消费者包装类
class WeakImageConsumer {
    /// 弱引用目标消费者
    weak var value: ImageConsumer?
    
    /// 目标索引
    let indexAtTarget: UInt
    
    /// 初始化
    /// - Parameters:
    ///   - value: 目标消费者
    ///   - indexAtTarget: 目标索引
    init(value: ImageConsumer, indexAtTarget: UInt) {
        self.indexAtTarget = indexAtTarget
        self.value = value
    }
}

/// 目标容器类，用于管理图像处理目标
public class TargetContainer: Sequence {
    /// 目标消费者数组
    var targets = [WeakImageConsumer]()
    
    /// 目标数量
    var count: Int { return targets.count }
    
    /// 用于线程安全的调度队列
    let dispatchQueue = DispatchQueue(
        label: "com.sunsetlakesoftware.GPUImage.targetContainerQueue", attributes: [])

    /// 初始化
    public init() {
    }

    /// 添加目标消费者
    /// - Parameters:
    ///   - target: 目标消费者
    ///   - indexAtTarget: 目标索引
    public func append(_ target: ImageConsumer, indexAtTarget: UInt) {
        dispatchQueue.async {
            self.targets.append(WeakImageConsumer(value: target, indexAtTarget: indexAtTarget))
        }
    }

    /// 创建迭代器
    /// - Returns: 返回一个包含(ImageConsumer, UInt)元组的迭代器
    public func makeIterator() -> AnyIterator<(ImageConsumer, UInt)> {
        var index = 0

        return AnyIterator { () -> (ImageConsumer, UInt)? in
            return self.dispatchQueue.sync {
                if index >= self.targets.count {
                    return nil
                }

                // 移除无效的弱引用
                while self.targets[index].value == nil {
                    self.targets.remove(at: index)
                    if index >= self.targets.count {
                        return nil
                    }
                }

                index += 1
                return (self.targets[index - 1].value!, self.targets[index - 1].indexAtTarget)
            }
        }
    }

    /// 移除所有目标消费者
    public func removeAll() {
        dispatchQueue.async {
            self.targets.removeAll()
        }
    }
}

/// 源容器类，用于管理图像处理源
public class SourceContainer {
    /// 源字典，以索引为键
    var sources: [UInt: ImageSource] = [:]

    /// 初始化源容器
    public init() {
    }

    /// 添加图像源
    /// - Parameters:
    ///   - source: 图像源
    ///   - maximumInputs: 最大输入数量
    /// - Returns: 返回分配的索引，如果已满则返回nil
    public func append(_ source: ImageSource, maximumInputs: UInt) -> UInt? {
        var currentIndex: UInt = 0
        while currentIndex < maximumInputs {
            if sources[currentIndex] == nil {
                sources[currentIndex] = source
                return currentIndex
            }
            currentIndex += 1
        }

        return nil
    }

    /// 插入图像源
    /// - Parameters:
    ///   - source: 图像源
    ///   - atIndex: 目标索引
    ///   - maximumInputs: 最大输入数量
    /// - Returns: 插入的索引
    public func insert(_ source: ImageSource, atIndex: UInt, maximumInputs: UInt) -> UInt {
        guard atIndex < maximumInputs else {
            fatalError(
                "ERROR: Attempted to set a source beyond the maximum number of inputs on this operation"
            )
        }
        sources[atIndex] = source
        return atIndex
    }

    /// 移除指定索引的图像源
    /// - Parameter index: 要移除的索引
    public func removeAtIndex(_ index: UInt) {
        sources[index] = nil
    }
}

/// 图像中继类，用于在图像处理管道中传递图像
public class ImageRelay: ImageProcessingOperation {
    /// 新图像回调
    public var newImageCallback: ((Texture) -> Void)?

    /// 源容器
    public let sources = SourceContainer()
    
    /// 目标容器
    public let targets = TargetContainer()
    
    /// 最大输入数量，固定为1
    public let maximumInputs: UInt = 1
    
    /// 是否阻止中继
    public var preventRelay: Bool = false

    /// 初始化
    public init() {
    }

    /// 传输上一帧图像
    /// - Parameters:
    ///   - target: 目标消费者
    ///   - atIndex: 目标索引
    public func transmitPreviousImage(to target: ImageConsumer, atIndex: UInt) {
        sources.sources[0]?.transmitPreviousImage(to: self, atIndex: 0)
    }

    /// 当新纹理可用时调用
    /// - Parameters:
    ///   - texture: 新纹理
    ///   - fromSourceIndex: 来源索引
    public func newTextureAvailable(_ texture: Texture, fromSourceIndex: UInt) {
        if let newImageCallback = newImageCallback {
            newImageCallback(texture)
        }
        if !preventRelay {
            relayTextureOnward(texture)
        }
    }

    /// 中继纹理到所有目标
    /// - Parameter texture: 要中继的纹理
    public func relayTextureOnward(_ texture: Texture) {
        // 需要重写以保证移除之前应用的锁
        //        for _ in targets {
        //            framebuffer.lock()
        //        }
        //        framebuffer.unlock()
        for (target, index) in targets {
            target.newTextureAvailable(texture, fromSourceIndex: index)
        }
    }
}
