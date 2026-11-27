import Foundation
import Testing
import BinaryCodable

// Regression tests for decoding untrusted input:
//  - a keyed value must stay inside its declared length,
//  - type-header normalization must stay linear,
//  - keyed lookup must not be a linear scan per key.
// The round-trip tests pin down that honest encodings keep decoding.

// MARK: - Wire helpers

private func u32(_ value: Int) -> [UInt8] {
    withUnsafeBytes(of: UInt32(value).littleEndian) { Array($0) }
}

private func str(_ value: String) -> [UInt8] {
    u32(value.utf8.count) + Array(value.utf8)
}

/// version 2 + magic + type header + payload
private func frame(header: String, payload: [UInt8]) -> Data {
    Data([2] + u32(0x4E54424E) + str(header) + payload)
}

private func seconds(_ body: () -> Void) -> Double {
    let start = Date()
    body()
    return Date().timeIntervalSince(start)
}

// MARK: - Models

private struct DHBlob: Codable, Equatable { var d: Data }
private struct DHPair: Codable, Equatable { var a: Data; var b: String }
private struct DHOne: Codable, Equatable { var n: Int }
private struct DHInner: Codable, Equatable { var id: UUID; var name: String; var blob: Data? }

private enum DHEvent: Codable, Equatable {
    case text(String, count: Int)
    case blob(Data?)
    case empty
    case nested(DHInner)
}

private struct DHModel: Codable, Equatable {
    var n: Int
    var u: UInt64
    var f: Float
    var s: String
    var o: DHInner?
    var missing: DHInner?
    var list: [DHInner]
    var events: [DHEvent]
    var last: DHEvent
    var meta: [String: Data]
    var deep: [String: [String: Int]]
    var byInt: [Int: String]
    var optionals: [String?]
}

/// Single-value wrapper around a non-optional value (the shape consumers use for identifiers).
private struct DHIdentifier: Codable, Equatable {
    var raw: String
    init(_ raw: String) { self.raw = raw }
    init(from decoder: Decoder) throws { raw = try decoder.singleValueContainer().decode(String.self) }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(raw)
    }
}

/// Single-value wrapper around an Optional: nil writes no bytes.
private struct DHNullable: Codable, Equatable {
    var value: String?
    init(_ value: String?) { self.value = value }
    init(from decoder: Decoder) throws { value = try decoder.singleValueContainer().decode(String?.self) }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }
}

private struct DHNullableParent: Codable, Equatable { var a: DHNullable; var id: DHIdentifier; var b: String }

/// Hand-written nested containers: one filled, one left empty as a marker.
private struct DHNested: Codable, Equatable {
    var kind: String
    var x: Int
    var y: Data
    enum K: String, CodingKey { case kind, payload, marker }
    enum P: String, CodingKey { case x, y }
    init(kind: String, x: Int, y: Data) { self.kind = kind; self.x = x; self.y = y }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        try c.encode(kind, forKey: .kind)
        var p = c.nestedContainer(keyedBy: P.self, forKey: .payload)
        try p.encode(x, forKey: .x)
        try p.encode(y, forKey: .y)
        _ = c.nestedContainer(keyedBy: P.self, forKey: .marker)
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        kind = try c.decode(String.self, forKey: .kind)
        let p = try c.nestedContainer(keyedBy: P.self, forKey: .payload)
        x = try p.decode(Int.self, forKey: .x)
        y = try p.decode(Data.self, forKey: .y)
        _ = try c.nestedContainer(keyedBy: P.self, forKey: .marker)
    }
}

/// A nested container that is still alive while a sibling is written gets a length that is
/// too long (it covers the sibling). Such encodings decode today and must keep decoding.
private struct DHLongLastEntry: Codable, Equatable {
    var v: Int
    var b: String
    enum K: String, CodingKey { case a, b }
    enum KA: String, CodingKey { case x }
    enum KX: String, CodingKey { case v }
    init(v: Int, b: String) { self.v = v; self.b = b }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        var n1 = c.nestedContainer(keyedBy: KA.self, forKey: .a)
        var n2 = n1.nestedContainer(keyedBy: KX.self, forKey: .x)
        try n2.encode(v, forKey: .v)
        try c.encode(b, forKey: .b)
        withExtendedLifetime(n1) {}
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        let n1 = try c.nestedContainer(keyedBy: KA.self, forKey: .a)
        let n2 = try n1.nestedContainer(keyedBy: KX.self, forKey: .x)
        v = try n2.decode(Int.self, forKey: .v)
        b = try c.decode(String.self, forKey: .b)
    }
}

private func roundTrip<T: Codable & Equatable>(_ value: T) throws {
    let encoded = try BinaryEncoder().encode(value)
    #expect(try BinaryDecoder().decode(T.self, from: encoded) == value)
    #expect(try BinaryDecoder(limits: .recommendedForUntrustedInput).decode(T.self, from: encoded) == value)
}

// MARK: - Tests

@Suite("Decoder hardening")
struct DecoderHardeningTests {

    // MARK: A value stays inside its declared length

    @Test("Values that overlap the rest of the input are rejected")
    func overlappingDataValuesAreRejected() throws {
        let n = 2_000
        let honest = Array(repeating: DHBlob(d: Data()), count: n)
        var bytes = [UInt8](try BinaryEncoder().encode(honest))
        #expect(try BinaryDecoder().decode([DHBlob].self, from: Data(bytes)) == honest)

        // Each element is 19 bytes and ends with the Data length. Point every length at the
        // end of the input: 38 KB would otherwise decode into about 38 MB.
        let elementSize = 19
        let start = bytes.count - n * elementSize
        for i in 0..<n {
            let lengthPosition = start + i * elementSize + elementSize - 4
            bytes.replaceSubrange(lengthPosition..<lengthPosition + 4, with: u32(bytes.count - lengthPosition - 4))
        }
        #expect(throws: DecodingError.self) {
            _ = try BinaryDecoder().decode([DHBlob].self, from: Data(bytes))
        }
        #expect(throws: DecodingError.self) {
            _ = try BinaryDecoder(limits: .recommendedForUntrustedInput).decode([DHBlob].self, from: Data(bytes))
        }
    }

    @Test("A value cannot read the bytes of the next entry")
    func valueCannotReadIntoNextEntry() throws {
        let entryB = str("b") + u32(7) + [1] + str("hi")
        // "a" declares 5 bytes (presence + Data length) but its Data length covers all of entry b.
        let entryA = str("a") + u32(5) + [1] + u32(entryB.count)
        let crafted = frame(header: String(reflecting: DHPair.self), payload: u32(2) + entryA + entryB)
        #expect(throws: DecodingError.self) {
            _ = try BinaryDecoder().decode(DHPair.self, from: crafted)
        }

        // Control: the same builder with honest lengths decodes.
        let honestA = str("a") + u32(7) + [1] + u32(2) + [0xAA, 0xBB]
        let honest = frame(header: String(reflecting: DHPair.self), payload: u32(2) + honestA + entryB)
        #expect(try BinaryDecoder().decode(DHPair.self, from: honest) == DHPair(a: Data([0xAA, 0xBB]), b: "hi"))
        #expect(honest == (try BinaryEncoder().encode(DHPair(a: Data([0xAA, 0xBB]), b: "hi"))))
    }

    @Test("A nil single-value Optional does not take its value from the next entry")
    func nilSingleValueDoesNotReadSibling() throws {
        try roundTrip(DHNullableParent(a: DHNullable(nil), id: DHIdentifier("abc"), b: "ATTACKER"))
        try roundTrip(DHNullableParent(a: DHNullable("x"), id: DHIdentifier(""), b: "tail"))
        try roundTrip(DHNullable(nil))
        try roundTrip(DHNullable("top"))
    }

    // MARK: Type header

    @Test("Type-header normalization stays linear on unclosed context segments")
    func headerNormalizationIsLinear() {
        let unit = "(unknowncontextat$"
        let header = String(repeating: unit, count: 64 * 1024 / unit.utf8.count)
        let crafted = frame(header: header, payload: [])
        var threw = false
        let elapsed = seconds {
            do { _ = try BinaryDecoder().decode(Int.self, from: crafted) } catch { threw = true }
        }
        #expect(threw)
        #expect(elapsed < 0.5, "64 KB header took \(elapsed) s")
    }

    @Test("Private types still match their header, whatever the address")
    func privateTypeHeaderStillMatches() throws {
        let value = DHOne(n: 7)
        let encoded = try BinaryEncoder().encode(value)
        #expect(try BinaryDecoder().decode(DHOne.self, from: encoded) == value)

        let header = String(reflecting: DHOne.self)
        #expect(header.contains("(unknown context at $"))
        let payload = [UInt8](encoded.dropFirst(1 + 4 + 4 + header.utf8.count))
        let otherLaunch = header.replacingOccurrences(of: "\\$[0-9a-fA-F]+", with: "\\$1f00dcafe", options: .regularExpression)
        #expect(otherLaunch != header)
        #expect(try BinaryDecoder().decode(DHOne.self, from: frame(header: otherLaunch, payload: payload)) == value)
        #expect(throws: DecodingError.self) {
            _ = try BinaryDecoder().decode(DHOne.self, from: frame(header: otherLaunch + "Other", payload: payload))
        }
    }

    @Test("A mismatched type header is capped and escaped in the error")
    func mismatchedHeaderIsCappedAndEscapedInError() {
        func mismatchText(header: String) -> String {
            do {
                _ = try BinaryDecoder().decode(DHOne.self, from: frame(header: header, payload: []))
                return ""
            } catch DecodingError.typeMismatch(let type, let context) {
                return "\(DecodingError.typeMismatch(type, context))"
            } catch {
                return ""
            }
        }

        // A header that tries to start a new log line and send terminal codes.
        let hostile = "Z\n2026-11-27T00:00:00Z critical [ Server ] FORGED" + "\u{1B}[2J" + "\u{9B}"
            + String(repeating: "A", count: 40_000)
        let text = mismatchText(header: hostile)
        #expect(text.contains("FORGED"))
        #expect(!text.unicodeScalars.contains { $0.value < 0x20 || (0x7F...0x9F).contains($0.value) })
        #expect(text.utf8.count < 2_048, "error text is \(text.utf8.count) bytes")

        // One character made of many scalars must not get around the cap.
        let stacked = "e" + String(repeating: "\u{301}", count: 40_000)
        #expect(mismatchText(header: stacked).utf8.count < 8_192)

        // Control: an ordinary mismatch reads as before and names both types.
        let ordinary = mismatchText(header: "Other.Module.Thing")
        #expect(ordinary.contains("normalized wire identity \"Thing\""))
        #expect(ordinary.contains("Original encoded header: Other.Module.Thing"))
        #expect(ordinary.contains("DHOne"))
    }

    // MARK: Keyed lookup

    @Test("Dictionary decoding does not scan every entry per key")
    func dictionaryDecodeIsNotQuadratic() throws {
        var dictionary: [String: Int] = [:]
        for i in 0..<8_000 { dictionary["key-\(i)"] = i }
        let encoded = try BinaryEncoder().encode(dictionary)
        var decoded: [String: Int] = [:]
        let elapsed = seconds { decoded = (try? BinaryDecoder().decode([String: Int].self, from: encoded)) ?? [:] }
        #expect(decoded == dictionary)
        #expect(elapsed < 1.0, "8,000 keys took \(elapsed) s")
    }

    @Test("Duplicate keys: the first one wins and is decoded once")
    func duplicateKeysFirstWinsAndDecodeOnce() throws {
        // Struct: first occurrence wins.
        let first = str("n") + u32(9) + [1] + [7, 0, 0, 0, 0, 0, 0, 0]
        let second = str("n") + u32(9) + [1] + [231, 3, 0, 0, 0, 0, 0, 0]
        let crafted = frame(header: String(reflecting: DHOne.self), payload: u32(2) + first + second)
        #expect(try BinaryDecoder().decode(DHOne.self, from: crafted) == DHOne(n: 7))

        // Dictionary: one large value followed by many duplicates of its key must not be
        // decoded once per duplicate.
        let big = [UInt8](repeating: 0x5A, count: 1_000_000)
        let duplicates = 30_000
        var payload = u32(1 + duplicates) + str("a") + u32(1 + 4 + big.count) + [1] + u32(big.count) + big
        let duplicate = str("a") + u32(5) + [1] + u32(0)
        for _ in 0..<duplicates { payload += duplicate }
        let input = frame(header: String(reflecting: [String: Data].self), payload: payload)
        var decoded: [String: Data] = [:]
        let elapsed = seconds { decoded = (try? BinaryDecoder().decode([String: Data].self, from: input)) ?? [:] }
        #expect(decoded == ["a": Data(big)])
        #expect(elapsed < 0.25, "30,000 duplicate keys took \(elapsed) s")
    }

    // MARK: Honest encodings keep decoding

    @Test("Honest encodings round-trip")
    func honestEncodingsRoundTrip() throws {
        let inner = DHInner(id: UUID(), name: "näme", blob: Data([1, 2, 3]))
        let bare = DHInner(id: UUID(), name: "", blob: nil)
        let model = DHModel(
            n: -5, u: .max, f: 1.5, s: "héllo", o: inner, missing: nil,
            list: [inner, bare],
            events: [.text("t", count: 2), .blob(Data([9])), .blob(nil), .empty, .nested(bare)],
            last: .nested(inner),
            meta: ["a": Data(), "b": Data(repeating: 7, count: 300)],
            deep: ["x": ["y": 1, "z": 2], "empty": [:]],
            byInt: [1: "one", -2: "minus two"],
            optionals: ["a", nil, ""]
        )
        try roundTrip(model)
        try roundTrip([model, model])
        try roundTrip(["k": [model]])
        try roundTrip(DHEvent.text("only", count: 1))
        try roundTrip([DHEvent.empty, .blob(nil)])
        try roundTrip(DHNested(kind: "k", x: 42, y: Data([1, 2])))
        try roundTrip([DHNested(kind: "k", x: 42, y: Data()), DHNested(kind: "", x: 0, y: Data([5]))])
        try roundTrip(DHLongLastEntry(v: 3, b: "xyz"))
        try roundTrip(["wrapped": DHLongLastEntry(v: 3, b: "xyz")])
        try roundTrip([DHIdentifier("a"), DHIdentifier("")])
        try roundTrip(Data([1, 2, 3]))
        try roundTrip("plain")
        try roundTrip([String: Int]())
        try roundTrip(Optional<DHInner>.none)
        try roundTrip(Optional(inner))
    }
}
