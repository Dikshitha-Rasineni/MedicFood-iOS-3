import UIKit

/// Where medicine photos and voice notes live on disk.
///
/// Medicines store only the *file name*, never an absolute path — the app's
/// container path changes between installs and updates, which would orphan
/// every saved image.
enum MediaStore {

    static var directory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("MedicFoodMedia", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func url(for name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    /// Saves as JPEG and returns the file name, or `nil` if it could not be written.
    static func saveImage(_ image: UIImage, prefix: String) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        let name = "\(prefix)-\(UUID().uuidString).jpg"
        do {
            try data.write(to: url(for: name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    static func image(named name: String?) -> UIImage? {
        guard let name else { return nil }
        return UIImage(contentsOfFile: url(for: name).path)
    }

    static func exists(_ name: String?) -> Bool {
        guard let name else { return false }
        return FileManager.default.fileExists(atPath: url(for: name).path)
    }

    static func delete(_ name: String?) {
        guard let name else { return }
        try? FileManager.default.removeItem(at: url(for: name))
    }
}

/// Joins several scanned pages into one tall image so OCR reads them in one pass.
enum ImageStitcher {
    static func combine(_ images: [UIImage]) -> UIImage? {
        guard let first = images.first else { return nil }
        guard images.count > 1 else { return first }

        let width = images.map(\.size.width).max() ?? first.size.width
        let heights = images.map { $0.size.height * (width / max($0.size.width, 1)) }
        let size = CGSize(width: width, height: heights.reduce(0, +))

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            var y: CGFloat = 0
            for (image, height) in zip(images, heights) {
                image.draw(in: CGRect(x: 0, y: y, width: width, height: height))
                y += height
            }
        }
    }
}
