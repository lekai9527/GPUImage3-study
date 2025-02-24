import Foundation
import Metal

// 着色器统一变量设置类
public class ShaderUniformSettings {
    // 统一变量查找表，键为变量名，值为索引
    let uniformLookupTable: [String: Int]
    // 统一变量值数组
    private var uniformValues: [Float]
    // 统一变量值偏移量数组
    private var uniformValueOffsets: [Int]
    // 颜色统一变量是否使用 alpha 通道
    public var colorUniformsUseAlpha: Bool = false
    // 用于同步访问统一变量设置的队列
    let shaderUniformSettingsQueue = DispatchQueue(
        label: "com.sunsetlakesoftware.GPUImage.shaderUniformSettings",
        attributes: [])

    // 初始化方法
    public init(uniformLookupTable: [String: (Int, MTLStructMember)], bufferSize: Int) {
        var convertedLookupTable: [String: Int] = [:]

        var orderedOffsets = [Int](repeating: 0, count: uniformLookupTable.count)

        for (key, uniform) in uniformLookupTable {
            let (index, structMember) = uniform
            convertedLookupTable[key] = index
            orderedOffsets[index] = structMember.offset / 4
        }

        self.uniformLookupTable = convertedLookupTable
        self.uniformValues = [Float](repeating: 0.0, count: bufferSize / 4)
        self.uniformValueOffsets = orderedOffsets
    }

    // 检查是否使用 aspectRatio 统一变量
    public var usesAspectRatio: Bool { return self.uniformLookupTable["aspectRatio"] != nil }

    // 获取内部索引
    private func internalIndex(for index: Int) -> Int {
        return uniformValueOffsets[index]
    }

    // MARK: -
    // MARK: 下标访问

    // 获取和设置浮点型统一变量
    public subscript(key: String) -> Float {
        get {
            guard let index = uniformLookupTable[key] else {
                fatalError(
                    "Tried to access value of missing uniform: \(key), make sure this is present and used in your shader."
                )
            }
            return uniformValues[internalIndex(for: index)]
        }
        set(newValue) {
            shaderUniformSettingsQueue.async {
                guard let index = self.uniformLookupTable[key] else {
                    fatalError(
                        "Tried to access value of missing uniform: \(key), make sure this is present and used in your shader."
                    )
                }
                self.uniformValues[self.internalIndex(for: index)] = newValue
            }
        }
    }

    // 获取和设置颜色型统一变量
    public subscript(key: String) -> Color {
        get {
            // TODO: Fix this
            return Color(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        }
        set(newValue) {
            shaderUniformSettingsQueue.async {
                let floatArray: [Float]
                guard let index = self.uniformLookupTable[key] else {
                    fatalError(
                        "Tried to access value of missing uniform: \(key), make sure this is present and used in your shader."
                    )
                }
                let startingIndex = self.internalIndex(for: index)
                if self.colorUniformsUseAlpha {
                    floatArray = newValue.toFloatArrayWithAlpha()
                    self.uniformValues[startingIndex] = floatArray[0]
                    self.uniformValues[startingIndex + 1] = floatArray[1]
                    self.uniformValues[startingIndex + 2] = floatArray[2]
                    self.uniformValues[startingIndex + 3] = floatArray[3]
                } else {
                    floatArray = newValue.toFloatArray()
                    self.uniformValues[startingIndex] = floatArray[0]
                    self.uniformValues[startingIndex + 1] = floatArray[1]
                    self.uniformValues[startingIndex + 2] = floatArray[2]
                }
            }
        }
    }

    // 获取和设置位置型统一变量
    public subscript(key: String) -> Position {
        get {
            // TODO: Fix this
            return Position(0.0, 0.0)
        }
        set(newValue) {
            shaderUniformSettingsQueue.async {
                let floatArray = newValue.toFloatArray()
                guard let index = self.uniformLookupTable[key] else {
                    fatalError(
                        "Tried to access value of missing uniform: \(key), make sure this is present and used in your shader."
                    )
                }
                var currentIndex = self.internalIndex(for: index)
                for floatValue in floatArray {
                    self.uniformValues[currentIndex] = floatValue
                    currentIndex += 1
                }
            }
        }
    }

    // 获取和设置大小型统一变量
    public subscript(key: String) -> Size {
        get {
            // TODO: Fix this
            return Size(width: 0.0, height: 0.0)
        }
        set(newValue) {
            shaderUniformSettingsQueue.async {
                let floatArray = newValue.toFloatArray()
                guard let index = self.uniformLookupTable[key] else {
                    fatalError(
                        "Tried to access value of missing uniform: \(key), make sure this is present and used in your shader."
                    )
                }
                var currentIndex = self.internalIndex(for: index)
                for floatValue in floatArray {
                    self.uniformValues[currentIndex] = floatValue
                    currentIndex += 1
                }
            }
        }
    }

    // 获取和设置 3x3 矩阵型统一变量
    public subscript(key: String) -> Matrix3x3 {
        get {
            // TODO: Fix this
            return Matrix3x3.identity
        }
        set(newValue) {
            shaderUniformSettingsQueue.async {
                let floatArray = newValue.toFloatArray()
                guard let index = self.uniformLookupTable[key] else {
                    fatalError(
                        "Tried to access value of missing uniform: \(key), make sure this is present and used in your shader."
                    )
                }
                var currentIndex = self.internalIndex(for: index)
                for floatValue in floatArray {
                    self.uniformValues[currentIndex] = floatValue
                    currentIndex += 1
                }
            }
        }
    }

    // 获取和设置 4x4 矩阵型统一变量
    public subscript(key: String) -> Matrix4x4 {
        get {
            // TODO: Fix this
            return Matrix4x4.identity
        }
        set(newValue) {
            shaderUniformSettingsQueue.async {
                let floatArray = newValue.toFloatArray()
                guard let index = self.uniformLookupTable[key] else {
                    fatalError(
                        "Tried to access value of missing uniform: \(key), make sure this is present and used in your shader."
                    )
                }
                var currentIndex = self.internalIndex(for: index)
                for floatValue in floatArray {
                    self.uniformValues[currentIndex] = floatValue
                    currentIndex += 1
                }
            }
        }
    }

    // MARK: -
    // MARK: 统一变量缓冲区内存管理

    // 恢复着色器设置
    public func restoreShaderSettings(renderEncoder: MTLRenderCommandEncoder) {
        shaderUniformSettingsQueue.sync {
            guard uniformValues.count > 0 else { return }

            let uniformBuffer = sharedMetalRenderingDevice.device.makeBuffer(
                bytes: uniformValues,
                length: uniformValues.count * MemoryLayout<Float>.size,
                options: [])!
            renderEncoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 1)
        }
    }
}

// 统一变量可转换协议
public protocol UniformConvertible {
    func toFloatArray() -> [Float]
}

// Float 类型实现 UniformConvertible 协议
extension Float: UniformConvertible {
    public func toFloatArray() -> [Float] {
        return [self]
    }
}

// Double 类型实现 UniformConvertible 协议
extension Double: UniformConvertible {
    public func toFloatArray() -> [Float] {
        return [Float(self)]
    }
}

// Color 类型实现 UniformConvertible 协议
extension Color {
    func toFloatArray() -> [Float] {
        return [self.redComponent, self.greenComponent, self.blueComponent, 0.0]
    }

    func toFloatArrayWithAlpha() -> [Float] {
        return [self.redComponent, self.greenComponent, self.blueComponent, self.alphaComponent]
    }
}

// Position 类型实现 UniformConvertible 协议
extension Position: UniformConvertible {
    public func toFloatArray() -> [Float] {
        if let z = self.z {
            return [self.x, self.y, z, 0.0]
        } else {
            return [self.x, self.y]
        }
    }
}

// Matrix3x3 类型实现 UniformConvertible 协议
extension Matrix3x3: UniformConvertible {
    public func toFloatArray() -> [Float] {
        // 行主序，带零填充
        return [m11, m12, m13, 0.0, m21, m22, m23, 0.0, m31, m32, m33, 0.0]
        //        return [m11, m12, m13, m21, m22, m23, m31, m32, m33]
    }
}

// Matrix4x4 类型实现 UniformConvertible 协议
extension Matrix4x4: UniformConvertible {
    public func toFloatArray() -> [Float] {
        // 行主序
        return [m11, m12, m13, m14, m21, m22, m23, m24, m31, m32, m33, m34, m41, m42, m43, m44]
        //        return [m11, m21, m31, m41, m12, m22, m32, m42, m13, m23, m33, m43, m14, m24, m34, m44]
    }
}

// Size 类型实现 UniformConvertible 协议
extension Size: UniformConvertible {
    public func toFloatArray() -> [Float] {
        return [self.width, self.height]
    }
}