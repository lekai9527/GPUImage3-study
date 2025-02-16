import Foundation

// 重新实现 CMTime 以便在 Linux 上使用
public struct TimestampFlags: OptionSet {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    // 时间戳有效
    public static let valid = TimestampFlags(rawValue: 1 << 0)
    // 时间戳已被舍入
    public static let hasBeenRounded = TimestampFlags(rawValue: 1 << 1)
    // 正无穷大
    public static let positiveInfinity = TimestampFlags(rawValue: 1 << 2)
    // 负无穷大
    public static let negativeInfinity = TimestampFlags(rawValue: 1 << 3)
    // 不确定
    public static let indefinite = TimestampFlags(rawValue: 1 << 4)
}

// 时间戳结构体，符合 Comparable 协议
public struct Timestamp: Comparable {
    // 时间戳的值
    let value: Int64
    // 时间戳的时标
    let timescale: Int32
    // 时间戳的标志
    let flags: TimestampFlags
    // 时间戳的纪元
    let epoch: Int64

    // 初始化方法
    public init(value: Int64, timescale: Int32, flags: TimestampFlags, epoch: Int64) {
        self.value = value
        self.timescale = timescale
        self.flags = flags
        self.epoch = epoch
    }

    // 将时间戳转换为秒
    func seconds() -> Double {
        return Double(value) / Double(timescale)
    }

    // 零时间戳
    public static let zero = Timestamp(value: 0, timescale: 0, flags: .valid, epoch: 0)
}

// 等于运算符重载
public func == (x: Timestamp, y: Timestamp) -> Bool {
    // TODO: Fix this
    //    if (x.flags.contains(TimestampFlags.PositiveInfinity) && y.flags.contains(TimestampFlags.PositiveInfinity)) {
    //        return true
    //    } else if (x.flags.contains(TimestampFlags.NegativeInfinity) && y.flags.contains(TimestampFlags.NegativeInfinity)) {
    //        return true
    //    } else if (x.flags.contains(TimestampFlags.Indefinite) || y.flags.contains(TimestampFlags.Indefinite) || x.flags.contains(TimestampFlags.NegativeInfinity) || y.flags.contains(TimestampFlags.NegativeInfinity) || x.flags.contains(TimestampFlags.PositiveInfinity) && y.flags.contains(TimestampFlags.PositiveInfinity)) {
    //        return false
    //    }

    // 如果时标不同，调整 y 的值以匹配 x 的时标
    let correctedYValue: Int64
    if x.timescale != y.timescale {
        correctedYValue = Int64(round(Double(y.value) * Double(x.timescale) / Double(y.timescale)))
    } else {
        correctedYValue = y.value
    }

    // 比较值和纪元
    return ((x.value == correctedYValue) && (x.epoch == y.epoch))
}

// 小于运算符重载
public func < (x: Timestamp, y: Timestamp) -> Bool {
    // TODO: Fix this
    //    if (x.flags.contains(TimestampFlags.PositiveInfinity) || y.flags.contains(TimestampFlags.NegativeInfinity)) {
    //        return false
    //    } else if (x.flags.contains(TimestampFlags.NegativeInfinity) || y.flags.contains(TimestampFlags.PositiveInfinity)) {
    //        return true
    //    }

    // 比较纪元
    if x.epoch < y.epoch {
        return true
    } else if x.epoch > y.epoch {
        return false
    }

    // 如果时标不同，调整 y 的值以匹配 x 的时标
    let correctedYValue: Int64
    if x.timescale != y.timescale {
        correctedYValue = Int64(round(Double(y.value) * Double(x.timescale) / Double(y.timescale)))
    } else {
        correctedYValue = y.value
    }

    // 比较值
    return (x.value < correctedYValue)
}
