import CoreImage
import UIKit

enum QRCodeRenderer {
    static func image(for url: URL, sideLength: CGFloat = 280) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(url.absoluteString.utf8), forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage else { return nil }

        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else { return nil }

        let moduleCount = outputImage.extent.width
        let quietZoneModules: CGFloat = 4
        let totalModules = moduleCount + quietZoneModules * 2
        let moduleSize = max(1, floor(sideLength / totalModules))
        let imageSize = CGSize(width: totalModules * moduleSize, height: totalModules * moduleSize)
        let codeRect = CGRect(
            x: quietZoneModules * moduleSize,
            y: quietZoneModules * moduleSize,
            width: moduleCount * moduleSize,
            height: moduleCount * moduleSize
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: imageSize, format: format).image { rendererContext in
            rendererContext.cgContext.setFillColor(UIColor.white.cgColor)
            rendererContext.cgContext.fill(CGRect(origin: .zero, size: imageSize))
            rendererContext.cgContext.interpolationQuality = .none
            UIImage(cgImage: cgImage).draw(in: codeRect)
        }
    }
}
