import Foundation

// MARK: - QR Payload Schema

/// V2 WiredPart QR code payload format.
///
/// Schema: `{"app":"wiredpart","version":2,"type":"<entity>","id":<int>,"code":"<string>","meta":{...}}`
///
/// Supported entity types: part, job, supplier, bin, vehicle, tool, employee, po
public struct QRPayload: Codable, Sendable, Equatable {
    public let app: String
    public let version: Int
    public let type: QREntityType
    public let id: Int64
    public let code: String
    public let meta: [String: String]?

    public init(
        type: QREntityType,
        id: Int64,
        code: String,
        meta: [String: String]? = nil
    ) {
        self.app = "wiredpart"
        self.version = 2
        self.type = type
        self.id = id
        self.code = code
        self.meta = meta
    }

    /// Returns true if this is a valid WiredPart QR payload.
    public var isValid: Bool {
        app == "wiredpart" && (version == 1 || version == 2) && !code.isEmpty
    }
}

// MARK: - QR Entity Types

/// The 8 entity types supported in V2 QR codes.
public enum QREntityType: String, Codable, Sendable, CaseIterable {
    case part
    case job
    case supplier
    case bin
    case vehicle
    case tool
    case employee
    case po
}

// MARK: - QR Scan Result

/// Result of scanning and decoding a QR code.
public enum QRDecodeResult: Sendable {
    /// Successfully decoded a WiredPart V2 payload.
    case wiredPartV2(QRPayload)
    /// Decoded a legacy V1 payload (no type field — treated as part).
    case wiredPartV1(id: Int64, code: String)
    /// Not a WiredPart QR — raw text payload for catalog search.
    case externalCode(String)
    /// Failed to decode.
    case invalid(reason: String)
}

// MARK: - QR Scan Event

/// Events emitted by continuous QR scanning.
public enum QRScanEvent: Sendable {
    case detected(payload: String, bounds: CGRect)
    case error(String)
    case permissionDenied
}

// MARK: - QR Codec

/// Encodes and decodes WiredPart QR code payloads.
///
/// Handles V1 backward compatibility: payloads without a `type` field
/// are treated as `type: "part"`.
public enum QRCodec {

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static let decoder = JSONDecoder()

    // MARK: - Encode

    /// Encode a QR payload to a JSON string for embedding in a QR code.
    public static func encode(_ payload: QRPayload) throws -> String {
        let data = try encoder.encode(payload)
        guard let string = String(data: data, encoding: .utf8) else {
            throw QRCodecError.encodingFailed
        }
        return string
    }

    // MARK: - Decode

    /// Decode a raw QR string into a structured result.
    ///
    /// Handles three cases:
    /// 1. Valid V2 WiredPart JSON → `QRDecodeResult.wiredPartV2`
    /// 2. V1 WiredPart JSON (no type) → `QRDecodeResult.wiredPartV1`
    /// 3. Non-WiredPart text → `QRDecodeResult.externalCode`
    public static func decode(_ rawString: String) -> QRDecodeResult {
        let trimmed = rawString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return .invalid(reason: "Empty QR payload")
        }

        // Attempt JSON parse
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let app = json["app"] as? String, app == "wiredpart" else {
            // Not a WiredPart QR — treat as external barcode/code
            return .externalCode(trimmed)
        }

        let version = json["version"] as? Int ?? 1

        // V2 payload — full structured decode
        if version >= 2 {
            do {
                let payload = try decoder.decode(QRPayload.self, from: data)
                guard payload.isValid else {
                    return .invalid(reason: "Invalid V2 payload: missing required fields")
                }
                return .wiredPartV2(payload)
            } catch {
                return .invalid(reason: "V2 JSON parse error: \(error.localizedDescription)")
            }
        }

        // V1 backward compatibility — no type field, treated as part
        if let id = json["id"] as? Int64,
           let code = json["code"] as? String {
            return .wiredPartV1(id: id, code: code)
        }

        // If it has the app marker but fails to parse
        return .invalid(reason: "Unrecognized WiredPart QR format")
    }
}

// MARK: - QR Codec Errors

public enum QRCodecError: Error, LocalizedError, Sendable {
    case encodingFailed
    case decodingFailed(String)
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode QR payload"
        case .decodingFailed(let reason):
            return "Failed to decode QR payload: \(reason)"
        case .unsupportedVersion(let v):
            return "Unsupported QR version: \(v)"
        }
    }
}
