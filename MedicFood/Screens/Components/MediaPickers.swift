import SwiftUI
import VisionKit
import PhotosUI
import AVFoundation

// MARK: - Document scanner (prescriptions)

/// Apple's document camera: finds the page, crops it, corrects perspective and
/// offers Retake / Keep Scan. Used for prescriptions.
struct DocumentScannerView: UIViewControllerRepresentable {
    var onScan: ([UIImage]) -> Void
    var onCancel: () -> Void
    var onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView
        init(parent: DocumentScannerView) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            parent.onScan(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.onError("Unable to scan the document. Please try again.")
        }
    }
}

// MARK: - Plain camera (medicine packaging)

/// A normal photo camera. Medicine front/back shots are not documents, so they
/// deliberately do not go through the document scanner.
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            } else {
                parent.onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }
    }
}

enum CameraAccess {
    static var isDenied: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return status == .denied || status == .restricted
    }
}

// MARK: - Image slot

/// One add / change / preview / remove image slot.
///
/// `usesDocumentScanner` picks the camera behaviour: the document scanner for
/// prescriptions, a normal camera for medicine packaging.
struct MedicineImageSlot: View {
    let title: String
    @Binding var image: UIImage?
    var usesDocumentScanner = false

    @Environment(\.openURL) private var openURL
    @State private var showCamera = false
    @State private var showPreview = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var alertMessage: String?
    @State private var offerSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                if image != nil {
                    Button("Remove", role: .destructive) { image = nil }
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(title) image")
                }
            }

            Button {
                if image != nil { showPreview = true }
            } label: {
                preview
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(image == nil ? "No \(title) image" : "Preview \(title) image")

            HStack(spacing: 10) {
                Button(action: openCamera) {
                    Label(image == nil ? "Camera" : "Retake", systemImage: usesDocumentScanner ? "doc.viewfinder" : "camera")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(.white)
                        .background(Theme.Colors.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.borderless)

                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(image == nil ? "Gallery" : "Change", systemImage: "photo")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let picked = UIImage(data: data) {
                    image = picked
                } else {
                    alertMessage = "Unable to load that photo."
                }
                pickerItem = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            camera.ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showPreview) {
            if let image { ImagePreview(image: image) }
        }
        .alert(alertMessage ?? "", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
            if offerSettings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
            Button("OK", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 220)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            VStack(spacing: 6) {
                Image(systemName: usesDocumentScanner ? "doc.text.viewfinder" : "photo.badge.plus")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.Colors.brand)
                Text("No image yet")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(Theme.Colors.page, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    @ViewBuilder
    private var camera: some View {
        if usesDocumentScanner {
            DocumentScannerView(
                onScan: { pages in
                    if let combined = ImageStitcher.combine(pages) { image = combined }
                    showCamera = false
                },
                onCancel: { showCamera = false },
                onError: { message in
                    showCamera = false
                    alertMessage = message
                }
            )
        } else {
            CameraPicker(
                onImage: { picked in
                    image = picked
                    showCamera = false
                },
                onCancel: { showCamera = false }
            )
        }
    }

    private func openCamera() {
        if usesDocumentScanner {
            guard VNDocumentCameraViewController.isSupported else {
                offerSettings = false
                alertMessage = "Document scanning isn't available on this device. Use Gallery instead."
                return
            }
        } else {
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                offerSettings = false
                alertMessage = "The camera isn't available on this device. Use Gallery instead."
                return
            }
        }
        guard !CameraAccess.isDenied else {
            offerSettings = true
            alertMessage = "Camera access is required. Turn it on for MedicFood in Settings."
            return
        }
        showCamera = true
    }
}

struct ImagePreview: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
            }
            .background(Color.white)
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
