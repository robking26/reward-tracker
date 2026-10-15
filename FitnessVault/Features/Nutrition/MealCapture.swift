import PhotosUI
import SwiftUI
import UIKit

extension View {
    /// Presents the meal camera (or the photo library where no camera exists), then the review sheet.
    /// - Parameters:
    ///   - isPresented: opens the camera.
    ///   - libraryPresented: opens the photo library instead.
    func mealCapture(isPresented: Binding<Bool>, libraryPresented: Binding<Bool> = .constant(false)) -> some View {
        modifier(MealCaptureModifier(isPresented: isPresented, libraryPresented: libraryPresented))
    }
}

private struct CapturedPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
    let takenAt: Date
}

private struct MealCaptureModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var libraryPresented: Bool
    @State private var showingCamera = false
    @State private var showingLibrary = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var captured: CapturedPhoto?

    private var hasCamera: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, presented in
                guard presented else { return }
                isPresented = false
                if hasCamera { showingCamera = true } else { showingLibrary = true }
            }
            .onChange(of: libraryPresented) { _, presented in
                guard presented else { return }
                libraryPresented = false
                showingLibrary = true
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { image in
                    showingCamera = false
                    if let image { captured = CapturedPhoto(image: image, takenAt: .now) }
                }
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: $showingLibrary, selection: $libraryItem, matching: .images)
            .onChange(of: libraryItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        captured = CapturedPhoto(image: image, takenAt: .now)
                    }
                    libraryItem = nil
                }
            }
            .sheet(item: $captured) { photo in
                MealReviewSheet(image: photo.image, takenAt: photo.takenAt)
            }
    }
}

/// The system camera. UIKit is used here only because SwiftUI has no native camera capture view.
struct CameraPicker: UIViewControllerRepresentable {
    var onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
