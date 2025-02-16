public enum ImageOrientation {
    // 竖屏方向
    case portrait
    // 竖屏方向（倒置）
    case portraitUpsideDown
    // 横屏方向（左）
    case landscapeLeft
    // 横屏方向（右）
    case landscapeRight

    // 计算从当前方向到目标方向所需的旋转
    func rotationNeeded(for targetOrientation: ImageOrientation) -> Rotation {
        switch (self, targetOrientation) {
        case (.portrait, .portrait), (.portraitUpsideDown, .portraitUpsideDown),
            (.landscapeLeft, .landscapeLeft), (.landscapeRight, .landscapeRight):
            return .noRotation
        case (.portrait, .portraitUpsideDown): return .rotate180
        case (.portraitUpsideDown, .portrait): return .rotate180
        case (.portrait, .landscapeLeft): return .rotateCounterclockwise
        case (.landscapeLeft, .portrait): return .rotateClockwise
        case (.portrait, .landscapeRight): return .rotateClockwise
        case (.landscapeRight, .portrait): return .rotateCounterclockwise
        case (.landscapeLeft, .landscapeRight): return .rotate180
        case (.landscapeRight, .landscapeLeft): return .rotate180
        case (.portraitUpsideDown, .landscapeLeft): return .rotateClockwise
        case (.landscapeLeft, .portraitUpsideDown): return .rotateCounterclockwise
        case (.portraitUpsideDown, .landscapeRight): return .rotateCounterclockwise
        case (.landscapeRight, .portraitUpsideDown): return .rotateClockwise
        }
    }
}

public enum Rotation {
    // 无旋转
    case noRotation
    // 逆时针旋转90度
    case rotateCounterclockwise
    // 顺时针旋转90度
    case rotateClockwise
    // 旋转180度
    case rotate180
    // 水平翻转
    case flipHorizontally
    // 垂直翻转
    case flipVertically
    // 顺时针旋转90度并垂直翻转
    case rotateClockwiseAndFlipVertically
    // 顺时针旋转90度并水平翻转
    case rotateClockwiseAndFlipHorizontally

    // 判断旋转是否会翻转尺寸
    func flipsDimensions() -> Bool {
        switch self {
        case .noRotation, .rotate180, .flipHorizontally, .flipVertically: return false
        case .rotateCounterclockwise, .rotateClockwise, .rotateClockwiseAndFlipVertically,
            .rotateClockwiseAndFlipHorizontally:
            return true
        }
    }
}
