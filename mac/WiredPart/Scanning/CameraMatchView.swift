import SwiftUI
import WiredPartCore

#if os(macOS)
import AppKit

// MARK: - Camera Match View (macOS)

/// View for camera-based part matching on macOS.
///
/// Allows the user to:
/// 1. Select an image file or take a photo with the webcam
/// 2. Extract features from the image
/// 3. View top-5 matching parts from the catalog
/// 4. Confirm a match to navigate to the part detail
struct CameraMatchView: View {
    @EnvironmentObject var appCore: AppCore
    @State private var selectedImage: NSImage?
    @State private var matchResults: [ImageMatchResult] = []
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showFilePicker = false

    private let featureAdapter = AppleImageFeatureAdapter()

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Label("Camera Part Match", systemImage: "camera.viewfinder")
                    .font(.title2)
                Spacer()
            }

            // Image selection area
            GroupBox {
                if let image = selectedImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 48))
                            .foregroundStyle(.tertiary)
                        Text("Select or photograph a part to find matches")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                }
            }

            // Actions
            HStack(spacing: 12) {
                Button("Choose Image...") {
                    chooseImage()
                }

                if selectedImage != nil {
                    Button("Find Matches") {
                        Task { await findMatches() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isProcessing)

                    Button("Clear") {
                        selectedImage = nil
                        matchResults = []
                        errorMessage = nil
                    }
                }

                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.7)
                }

                Spacer()
            }

            // Error
            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
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

                            // Similarity score
                            ConfidenceIndicator(confidence: result.similarity)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.secondary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .padding()
    }

    // MARK: - Actions

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]

        if panel.runModal() == .OK, let url = panel.url {
            selectedImage = NSImage(contentsOf: url)
        }
    }

    private func findMatches() async {
        guard let nsImage = selectedImage,
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
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
                errorMessage = "No matching parts found. Try with better lighting or a closer photo."
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isProcessing = false
    }
}

#endif
