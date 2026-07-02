import SwiftUI
import WiredPartCore

import UIKit
import PhotosUI

// MARK: - iOS Camera Match View

/// Camera-based part matching view for iOS.
///
/// Supports both camera capture and photo library selection.
/// Touch-optimized with larger tap targets and haptic feedback.
struct IOSCameraMatchView: View {
    @EnvironmentObject var appCore: AppCore
    @State private var selectedImage: UIImage?
    @State private var matchResults: [ImageMatchResult] = []
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var photoPickerItem: PhotosPickerItem?

    private let featureAdapter = IOSImageFeatureAdapter()

    /// Whether this device can present the system camera. False on Simulator,
    /// camera-less hardware, and restricted devices — presenting a `.camera`
    /// picker in those environments crashes or shows a dead system flow (#1080).
    private var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Image area
                GroupBox {
                    if let image = selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "camera.viewfinder")
                                .decorativeIconFont(48)
                                .foregroundStyle(.tertiary)
                            Text("Take a photo or select an image")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                    }
                }

                // Action buttons
                HStack(spacing: 16) {
                    Button {
                        // Defense in depth: the button is disabled when the camera is
                        // unavailable, but never present a `.camera` picker without the
                        // hardware check (#1080).
                        guard isCameraAvailable else {
                            errorMessage = "Camera is not available on this device. Use Photos instead."
                            return
                        }
                        showCamera = true
                    } label: {
                        Label("Camera", systemImage: "camera.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!isCameraAvailable)
                    .accessibilityHint(
                        isCameraAvailable
                            ? "Take a photo of the part to match."
                            : "Camera is not available on this device. Use Photos instead."
                    )

                    PhotosPicker(
                        selection: $photoPickerItem,
                        matching: .images
                    ) {
                        Label("Photos", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.bordered)

                    if selectedImage != nil {
                        Button {
                            Task { await findMatches() }
                        } label: {
                            Label("Match", systemImage: "magnifyingglass")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isProcessing)
                    }
                }

                // Fallback guidance when no camera hardware is present (#1080)
                if !isCameraAvailable {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.badge.ellipsis")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text("Camera isn't available on this device — use Photos to select an image instead.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if isProcessing {
                    ProgressView("Matching...")
                }

                // Error
                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        Text(error)
                            .font(.callout)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Results
                if !matchResults.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Matches")
                            .font(.headline)

                        ForEach(matchResults) { result in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(result.partName)
                                        .font(.body)
                                    if let code = result.partCode {
                                        Text(code)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                IOSConfidenceIndicator(confidence: result.similarity)
                            }
                            .padding()
                            .background(Color.secondary.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Part Match")
        .fullScreenCover(isPresented: $showCamera) {
            CameraCapture(image: $selectedImage)
        }
        .task(id: photoPickerItem) {
            await loadPhotoPickerItem(photoPickerItem)
        }
    }

    // MARK: - Photo Import

    private func loadPhotoPickerItem(_ item: PhotosPickerItem?) async {
        guard let item else { return }

        await MainActor.run {
            selectedImage = nil
            matchResults = []
            errorMessage = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    errorMessage = "Could not load that photo. Try another image or use Camera."
                }
                return
            }
            try Task.checkCancellation()

            guard let uiImage = UIImage(data: data) else {
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    errorMessage = "Could not read that photo. Try another image or use Camera."
                }
                return
            }
            try Task.checkCancellation()

            await MainActor.run {
                selectedImage = uiImage
                matchResults = []
                errorMessage = nil
            }
        } catch {
            guard !Task.isCancelled else { return }

            await MainActor.run {
                errorMessage = "Could not load that photo. Try another image or use Camera."
            }
        }
    }

    // MARK: - Match

    private func findMatches() async {
        guard let uiImage = selectedImage,
              let cgImage = uiImage.cgImage else {
            errorMessage = "Failed to process image"
            return
        }

        isProcessing = true
        errorMessage = nil

        do {
            let vector = try await featureAdapter.extractFeatures(from: cgImage)

            guard let db = appCore.db else {
                errorMessage = "Database not available"
                isProcessing = false
                return
            }

            let matcher = ImageMatcher(db: db)
            try await matcher.loadIndex(adapterType: featureAdapter.adapterType)
            matchResults = try await matcher.search(queryVector: vector, topN: 5)

            if matchResults.isEmpty {
                errorMessage = "No matching parts found."
            }

            // Haptic feedback on results
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(matchResults.isEmpty ? .warning : .success)

        } catch {
            errorMessage = userFriendlyError(error, context: "match item")
        }

        isProcessing = false
    }
}

// MARK: - Camera Capture

/// UIImagePickerController wrapper for camera capture.
struct CameraCapture: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        // Never force `.camera` when the hardware isn't available (Simulator,
        // camera-less or restricted devices) — UIImagePickerController raises an
        // exception for unavailable source types. Fall back to the photo library
        // so the flow stays usable instead of crashing (#1080).
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
        } else {
            picker.sourceType = .photoLibrary
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCapture

        init(_ parent: CameraCapture) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

