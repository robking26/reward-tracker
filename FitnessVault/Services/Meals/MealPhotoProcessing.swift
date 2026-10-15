import UIKit

enum MealPhotoProcessing {
    /// Resizes to at most `maxPixel` on the long edge and re-encodes as JPEG, which also strips location metadata.
    static func jpeg(from image: UIImage, maxPixel: CGFloat, quality: CGFloat = 0.75) -> Data? {
        let size = image.size
        let scale = min(1, maxPixel / max(size.width, size.height, 1))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
