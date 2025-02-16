public struct Color {
    // 红色分量
    public let redComponent: Float
    // 绿色分量
    public let greenComponent: Float
    // 蓝色分量
    public let blueComponent: Float
    // 透明度分量
    public let alphaComponent: Float

    // 初始化方法
    public init(red: Float, green: Float, blue: Float, alpha: Float = 1.0) {
        self.redComponent = red
        self.greenComponent = green
        self.blueComponent = blue
        self.alphaComponent = alpha
    }

    // 预定义颜色常量
    public static let black = Color(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
    public static let white = Color(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
    public static let red = Color(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
    public static let green = Color(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0)
    public static let blue = Color(red: 0.0, green: 0.0, blue: 1.0, alpha: 1.0)
    public static let transparent = Color(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
}
