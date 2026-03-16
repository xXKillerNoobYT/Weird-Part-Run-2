import Testing
import Foundation
@testable import WiredPartCore

@Suite("QR Codec Tests")
struct QRCodecTests {

    // MARK: - Encode Tests

    @Test("Encode V2 payload produces valid JSON")
    func testEncodeV2Payload() throws {
        let payload = QRPayload(type: .part, id: 42, code: "WIRE-001")
        let json = try QRCodec.encode(payload)

        #expect(json.contains("\"app\":\"wiredpart\""))
        #expect(json.contains("\"version\":2"))
        #expect(json.contains("\"type\":\"part\""))
        #expect(json.contains("\"id\":42"))
        #expect(json.contains("\"code\":\"WIRE-001\""))
    }

    @Test("Encode V2 payload with metadata")
    func testEncodeWithMeta() throws {
        let payload = QRPayload(
            type: .bin, id: 7, code: "BIN-A3",
            meta: ["location": "Warehouse 1"]
        )
        let json = try QRCodec.encode(payload)
        #expect(json.contains("\"location\":\"Warehouse 1\""))
    }

    // MARK: - Decode Tests

    @Test("Decode V2 WiredPart QR")
    func testDecodeV2() {
        let json = """
        {"app":"wiredpart","version":2,"type":"job","id":99,"code":"JOB-123"}
        """
        let result = QRCodec.decode(json)

        if case .wiredPartV2(let payload) = result {
            #expect(payload.type == .job)
            #expect(payload.id == 99)
            #expect(payload.code == "JOB-123")
        } else {
            Issue.record("Expected wiredPartV2, got \(result)")
        }
    }

    @Test("Decode V1 backward compatibility — treated as part")
    func testDecodeV1() {
        let json = """
        {"app":"wiredpart","version":1,"id":10,"code":"PART-OLD"}
        """
        let result = QRCodec.decode(json)

        if case .wiredPartV1(let id, let code) = result {
            #expect(id == 10)
            #expect(code == "PART-OLD")
        } else {
            Issue.record("Expected wiredPartV1, got \(result)")
        }
    }

    @Test("Decode non-WiredPart text returns externalCode")
    func testDecodeExternalCode() {
        let result = QRCodec.decode("SKU12345678")

        if case .externalCode(let text) = result {
            #expect(text == "SKU12345678")
        } else {
            Issue.record("Expected externalCode")
        }
    }

    @Test("Decode empty string returns invalid")
    func testDecodeEmpty() {
        let result = QRCodec.decode("")
        if case .invalid = result {
            // Expected
        } else {
            Issue.record("Expected invalid for empty string")
        }
    }

    @Test("Decode malformed JSON returns externalCode")
    func testDecodeMalformedJSON() {
        let result = QRCodec.decode("{not valid json}")
        if case .externalCode = result {
            // Expected — not WiredPart, treated as external
        } else {
            Issue.record("Expected externalCode for malformed JSON")
        }
    }

    @Test("Round-trip encode/decode preserves data")
    func testRoundTrip() throws {
        let original = QRPayload(
            type: .supplier, id: 55, code: "SUP-ACE",
            meta: ["phone": "555-0100"]
        )
        let encoded = try QRCodec.encode(original)
        let decoded = QRCodec.decode(encoded)

        if case .wiredPartV2(let payload) = decoded {
            #expect(payload == original)
        } else {
            Issue.record("Round-trip failed")
        }
    }

    // MARK: - Entity Type Tests

    @Test("All 8 entity types round-trip correctly")
    func testAllEntityTypes() throws {
        for entityType in QREntityType.allCases {
            let payload = QRPayload(type: entityType, id: 1, code: "TEST")
            let encoded = try QRCodec.encode(payload)
            let decoded = QRCodec.decode(encoded)

            if case .wiredPartV2(let result) = decoded {
                #expect(result.type == entityType, "Entity type \(entityType) failed round-trip")
            } else {
                Issue.record("Entity type \(entityType) decode failed")
            }
        }
    }

    // MARK: - QR Payload Validation

    @Test("Payload isValid check")
    func testPayloadValidation() {
        let valid = QRPayload(type: .part, id: 1, code: "VALID")
        #expect(valid.isValid)
    }
}
