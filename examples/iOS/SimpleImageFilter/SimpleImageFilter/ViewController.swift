import GPUImage
import UIKit

class ViewController: UIViewController {

    @IBOutlet weak var renderView: RenderView! // 用于显示处理后的图像的视图

    var picture: PictureInput! // GPUImage的图片输入对象
    var filter: SaturationAdjustment! // GPUImage的饱和度调整滤镜

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Filtering image for saving
        // 加载测试图片
        let testImage = UIImage(named: "WID-small.jpg")!
        // 创建一个卡通化滤镜
        let toonFilter = ToonFilter()
        // 对图片应用滤镜，生成处理后的图片
        let filteredImage = testImage.filterWithOperation(toonFilter)

        // 将处理后的图片转换为PNG格式的数据
        let pngImage = UIImagePNGRepresentation(filteredImage)!
        do {
            // 获取应用的文档目录
            let documentsDir = try FileManager.default.url(
                for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            // 创建文件URL
            let fileURL = URL(string: "test.png", relativeTo: documentsDir)!
            // 将PNG数据写入文件
            try pngImage.write(to: fileURL, options: .atomic)
        } catch {
            // 如果写入文件失败，打印错误信息
            print("Couldn't write to file with error: \(error)")
        }

        // Filtering image for display
        // 初始化GPUImage的图片输入对象，加载同一张图片
        picture = PictureInput(image: UIImage(named: "WID-small.jpg")!)
        // 初始化GPUImage的饱和度调整滤镜
        filter = SaturationAdjustment()
        // 将图片输入、滤镜和渲染视图连接起来：图片 --> 滤镜 --> 渲染视图
        picture --> filter --> renderView
        // 处理图片并显示在渲染视图中
        picture.processImage()
    }
}
