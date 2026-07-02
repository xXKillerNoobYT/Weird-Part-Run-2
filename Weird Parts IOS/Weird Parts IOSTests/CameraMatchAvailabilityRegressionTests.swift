import XCTest

/// Regression coverage for GH #1080: the Part Match camera flow must never
/// present a `.camera` UIImagePickerController without first checking
/// `UIImagePickerController.isSourceTypeAvailable(.camera)`. On Simulator,
/// camera-less iPads, and restricted devices the unguarded flow crashed or
/// presented a dead system picker.
final class CameraMatchAvailabilityRegressionTests: XCTestCase {

    func testCameraButtonGuardsAvailabilityBeforePresentingCapture() throws {
        let source = try Self.readCameraMatchSource()

        XCTAssertTrue(
            source.contains("UIImagePickerController.isSourceTypeAvailable(.camera)"),
            "IOSCameraMatchView must check camera availability via UIImagePickerController.isSourceTypeAvailable(.camera)."
        )
        XCTAssertTrue(
            source.contains("guard isCameraAvailable else {"),
            "The Camera button action must guard on camera availability before presenting capture."
        )

        // The availability guard must run BEFORE the capture sheet is triggered.
        let availabilityGuard = try XCTUnwrap(source.range(of: "guard isCameraAvailable else {"))
        let showCameraTrigger = try XCTUnwrap(source.range(of: "showCamera = true"))
        XCTAssertTrue(
            availabilityGuard.lowerBound < showCameraTrigger.lowerBound,
            "The camera availability guard must precede `showCamera = true` so the capture flow cannot open on camera-less devices."
        )

        XCTAssertTrue(
            source.contains(".disabled(!isCameraAvailable)"),
            "The Camera button must be disabled when no camera hardware is available."
        )
        XCTAssertTrue(
            source.contains("Camera is not available on this device. Use Photos instead."),
            "The unavailable-camera path must surface user-facing fallback guidance toward the Photos picker."
        )
    }

    func testCameraCaptureNeverForcesCameraSourceWithoutAvailabilityCheck() throws {
        let source = try Self.readCameraMatchSource()

        // Within makeUIViewController, the `.camera` source assignment must be
        // preceded by an availability check between the picker construction and
        // the assignment — an unconditional `picker.sourceType = .camera` is the
        // exact regression this test exists to catch.
        let pickerConstruction = try XCTUnwrap(
            source.range(of: "let picker = UIImagePickerController()"),
            "CameraCapture must construct a UIImagePickerController."
        )
        let cameraAssignment = try XCTUnwrap(
            source.range(of: "picker.sourceType = .camera", range: pickerConstruction.upperBound..<source.endIndex),
            "CameraCapture must still support the camera source when available."
        )
        let guardedRegion = String(source[pickerConstruction.upperBound..<cameraAssignment.lowerBound])
        XCTAssertTrue(
            guardedRegion.contains("if UIImagePickerController.isSourceTypeAvailable(.camera)"),
            "`picker.sourceType = .camera` must be gated behind UIImagePickerController.isSourceTypeAvailable(.camera)."
        )

        XCTAssertTrue(
            source.contains("picker.sourceType = .photoLibrary"),
            "CameraCapture must fall back to the photo library when camera hardware is unavailable."
        )
    }

    private static func readCameraMatchSource(file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Scanning")
            .appendingPathComponent("IOSCameraMatchView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
