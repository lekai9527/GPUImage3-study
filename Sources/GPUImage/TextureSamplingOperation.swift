open class TextureSamplingOperation: BasicOperation {
    // public var overriddenTexelSize:Size?

    // 初始化方法
    override public init(
        vertexFunctionName: String? = "nearbyTexelSampling",
        fragmentFunctionName: String,
        numberOfInputs: UInt = 1,
        operationName: String = #file
    ) {
        // 调用父类的初始化方法
        super.init(
            vertexFunctionName: vertexFunctionName, fragmentFunctionName: fragmentFunctionName,
            numberOfInputs: numberOfInputs, operationName: operationName)
        // 设置是否使用归一化的纹理坐标
        self.useNormalizedTextureCoordinates = false
    }
}
