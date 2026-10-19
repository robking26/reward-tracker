import PDFKit
import SwiftUI
import UIKit
import Vision
import VisionKit

/// On-device text recognition for recipes and receipts (F7, I3). Nothing leaves the phone.
enum TextRecognition {
    /// Reads the text in an image, top to bottom.
    nonisolated static func text(in image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }
        let imageOrientation = orientation(image.imageOrientation)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["en-GB"]
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: imageOrientation)
                try? handler.perform([request])
                let lines = (request.results ?? [])
                    .sorted { $0.boundingBox.minY > $1.boundingBox.minY }
                    .compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
        }
    }

    /// Text from several images (pages of a scan), in order.
    nonisolated static func text(in images: [UIImage]) async -> String {
        var pages: [String] = []
        for image in images { pages.append(await text(in: image)) }
        return pages.joined(separator: "\n")
    }

    /// Text from a PDF: its own text layer where there is one, otherwise recognised from rendered pages.
    /// At most `maxPages`, so a whole recipe book isn't read at once.
    nonisolated static func text(inPDF url: URL, maxPages: Int = 6) async -> String {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let document = PDFDocument(url: url) else { return "" }
        let count = min(document.pageCount, maxPages)
        var embedded = ""
        for index in 0..<count { embedded += (document.page(at: index)?.string ?? "") + "\n" }
        if embedded.trimmingCharacters(in: .whitespacesAndNewlines).count > 40 { return embedded }
        var images: [UIImage] = []
        for index in 0..<count {
            guard let page = document.page(at: index) else { continue }
            images.append(page.thumbnail(of: CGSize(width: 1600, height: 2200), for: .mediaBox))
        }
        return await text(in: images)
    }

    /// Plain text or an image file chosen in Files.
    nonisolated static func text(inFile url: URL) async -> String {
        if url.pathExtension.lowercased() == "pdf" { return await text(inPDF: url) }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        if let data = try? Data(contentsOf: url) {
            if let image = UIImage(data: data) { return await text(in: image) }
            if let string = String(data: data, encoding: .utf8) { return string }
        }
        return ""
    }

    nonisolated private static func orientation(_ orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}

/// The system document camera: edge detection and perspective correction for recipe pages and receipts.
struct DocumentScanner: UIViewControllerRepresentable {
    var onFinish: ([UIImage]) -> Void
    var onCancel: () -> Void

    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScanner

        init(_ parent: DocumentScanner) {
            self.parent = parent
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let images = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            parent.onFinish(images)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.onCancel()
        }
    }
}
