//
//  BinaryDecoder.swift
//  binary-codable
//
//  Created by Cole M on 11/18/25.
//
//  Copyright (c) 2025 NeedleTails Organization.
//
//  This project is licensed under the MIT License.
//
//  See the LICENSE file for more information.
//

import Foundation

// MARK: - Public entry point

public struct BinaryDecoder: Sendable {
    
    /// The Magic header used to reliably detect what kind of data we are looking at before trying to parse it.
    private static let magic: UInt32 = 0x4E54424E
    
    public init() {}
    
    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        // 1) Read and validate version
        guard !data.isEmpty else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [],
                      debugDescription: "Empty data; missing version byte")
            )
        }
        
        let version = data[0]
        
        let storage = DecoderStorage(data: data, version: version)
        storage.advanceOffset(1)  // Skip version byte
        let core = _BinaryDecoder(storage: storage)
        
        guard version >= 1 else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [],
                      debugDescription: "Unsupported binary format version \(version)")
            )
        }
        
        if version == 1 {
            // magic optional
            let afterVersion = storage.offset
            if storage.offset + 4 <= storage.data.count {
                let possibleMagic = try core.readUInt32()
                if possibleMagic != BinaryDecoder.magic {
                    storage.setOffset(afterVersion) // old v1
                }
            }
        } else if version >= 2 {
            // magic required, native UInt64 and Float support (version 2+)
            let m = try core.readUInt32()
            guard m == BinaryDecoder.magic else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: storage.codingPath,
                    debugDescription: "Bad magic header"
                ))
            }
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: storage.codingPath,
                debugDescription: "Unsupported version \(version)"
            ))
        }
        
        // 2) Read encoded type name and compare via descriptors
        let encodedTypeNameRaw = try core.readString()
        let encodedDesc   = descriptor(fromEncodedName: encodedTypeNameRaw)
        let requestedDesc = descriptor(for: T.self)
        
        guard areCompatible(encodedDesc, requestedDesc) else {
            throw DecodingError.typeMismatch(
                T.self,
                .init(
                    codingPath: storage.codingPath,
                    debugDescription: "Type mismatch: encoded as \(encodedTypeNameRaw), requested \(String(reflecting: T.self))"
                )
            )
        }
        
        // 3) Decode payload using your existing logic
        let value: T
        if type == Data.self {
            let result = try core.readData()
            value = result as! T
        } else {
            value = try T(from: core)
        }
        
        // 4) Ensure no trailing bytes remain
        if storage.offset != storage.data.count {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: storage.codingPath,
                    debugDescription: "Trailing bytes after decoding \(T.self): consumed \(storage.offset) of \(storage.data.count)"
                )
            )
        }
        
        return value
    }
}

// MARK: - Shared state (storage)

fileprivate final class DecoderStorage: @unchecked Sendable {
    private(set) var data: Data
    private(set) var offset: Int
    private(set) var codingPath: [CodingKey]
    let version: UInt8  // Track version for backward compatibility
    
    init(data: Data, offset: Int = 0, codingPath: [CodingKey] = [], version: UInt8 = 2) {
        self.data = data
        self.offset = offset
        self.codingPath = codingPath
        self.version = version
    }
    
    func advanceOffset(_ offset: Int) {
        self.offset += offset
    }
    
    func setOffset(_ offset: Int) {
        self.offset = offset
    }
    
    func setCodingPath(_ codingPath: [CodingKey]) {
        self.codingPath = codingPath
    }
    
    func appendCodingPath(_ key: CodingKey) {
        self.codingPath.append(key)
    }
    
    func removeLastKey() {
        self.codingPath.removeLast()
    }
    
    func setData(_ data: Data) {
        self.data = data
    }
}

// MARK: - Internal backing decoder

fileprivate struct _BinaryDecoder: Decoder, @unchecked Sendable {
    
    let storage: DecoderStorage
    
    var codingPath: [CodingKey] {
        get { storage.codingPath }
        set { storage.setCodingPath(newValue) }
    }
    
    var userInfo: [CodingUserInfoKey : Any] = [:]
    
    // MARK: - Required container methods
    
    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key: CodingKey {
        let container = try BinaryKeyedDecodingContainer<Key>(decoder: self)
        return KeyedDecodingContainer(container)
    }
    
    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        return BinaryUnkeyedDecodingContainer(decoder: self)
    }
    
    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        return BinarySingleValueDecodingContainer(decoder: self)
    }
    
    // MARK: - Low-level readers (must match the encoder format)
    
    func readData() throws -> Data {
        let lenSize = 4 // UInt32
        let offset = storage.offset
        let d = storage.data
        
        guard offset + lenSize <= d.count else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: codingPath,
                      debugDescription: "Unexpected end of data while reading Data length")
            )
        }
        
        let b0 = UInt32(d[offset])
        let b1 = UInt32(d[offset + 1]) << 8
        let b2 = UInt32(d[offset + 2]) << 16
        let b3 = UInt32(d[offset + 3]) << 24
        let lengthUInt32 = b0 | b1 | b2 | b3
        
        // UInt32 → Int safe conversion
        let length = Int(lengthUInt32)
        
        storage.advanceOffset(lenSize)
        
        guard storage.offset + length <= d.count else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: codingPath,
                      debugDescription: "Unexpected end of data while reading Data bytes")
            )
        }
        
        let slice = d[storage.offset ..< storage.offset + length]
        storage.advanceOffset(length)
        return Data(slice)
    }
    
    func readUUID() throws -> UUID {
        let size = 16
        let offset = storage.offset
        let d = storage.data
        
        guard offset + size <= d.count else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: codingPath,
                      debugDescription: "Unexpected end of data while reading UUID")
            )
        }
        
        let bytes: uuid_t = (
            d[offset + 0], d[offset + 1], d[offset + 2], d[offset + 3],
            d[offset + 4], d[offset + 5], d[offset + 6], d[offset + 7],
            d[offset + 8], d[offset + 9], d[offset + 10], d[offset + 11],
            d[offset + 12], d[offset + 13], d[offset + 14], d[offset + 15]
        )
        
        storage.advanceOffset(size)
        return UUID(uuid: bytes)
    }
    
    func readBool() throws -> Bool {
        let offset = storage.offset
        let d = storage.data
        
        guard offset < d.count else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: codingPath,
                      debugDescription: "Unexpected end of data while reading Bool")
            )
        }
        
        let b = d[offset]
        storage.advanceOffset(1)
        return b != 0
    }
    
    func readInt64() throws -> Int64 {
        let size = 8
        let offset = storage.offset
        let d = storage.data
        
        guard offset + size <= d.count else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: codingPath,
                      debugDescription: "Unexpected end of data while reading Int64")
            )
        }
        
        var bits: UInt64 = 0
        for i in 0..<size {
            bits |= UInt64(d[offset + i]) << (UInt64(i) * 8)
        }
        
        storage.advanceOffset(size)
        return Int64(bitPattern: bits)
    }
    
    func readUInt64() throws -> UInt64 {
        let size = 8
        let offset = storage.offset
        let d = storage.data
        
        guard offset + size <= d.count else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: codingPath,
                      debugDescription: "Unexpected end of data while reading UInt64")
            )
        }
        
        var bits: UInt64 = 0
        for i in 0..<size {
            bits |= UInt64(d[offset + i]) << (UInt64(i) * 8)
        }
        
        storage.advanceOffset(size)
        return bits
    }
    
    func readDouble() throws -> Double {
        let size = 8
        let offset = storage.offset
        let d = storage.data
        
        guard offset + size <= d.count else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: codingPath,
                      debugDescription: "Unexpected end of data while reading Double")
            )
        }
        
        var bits: UInt64 = 0
        for i in 0..<size {
            bits |= UInt64(d[offset + i]) << (UInt64(i) * 8)
        }
        
        storage.advanceOffset(size)
        return Double(bitPattern: bits)
    }
    
    func readFloat() throws -> Float {
        let size = 4
        let offset = storage.offset
        let d = storage.data
        
        guard offset + size <= d.count else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: codingPath,
                      debugDescription: "Unexpected end of data while reading Float")
            )
        }
        
        var bits: UInt32 = 0
        for i in 0..<size {
            bits |= UInt32(d[offset + i]) << (UInt32(i) * 8)
        }
        
        storage.advanceOffset(size)
        return Float(bitPattern: bits)
    }
    
    func readString() throws -> String {
        let lenSize = 4
        let offset = storage.offset
        let d = storage.data
        
        guard offset + lenSize <= d.count else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: codingPath,
                      debugDescription: "Unexpected end of data while reading String length")
            )
        }
        
        let b0 = UInt32(d[offset])
        let b1 = UInt32(d[offset + 1]) << 8
        let b2 = UInt32(d[offset + 2]) << 16
        let b3 = UInt32(d[offset + 3]) << 24
        let lengthUInt32 = b0 | b1 | b2 | b3
        let length = Int(lengthUInt32)
        
        storage.advanceOffset(lenSize)
        
        guard storage.offset + length <= d.count else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: codingPath,
                      debugDescription: "Unexpected end of data while reading String bytes")
            )
        }
        
        let slice = d[storage.offset ..< storage.offset + length]
        storage.advanceOffset(length)
        
        guard let str = String(data: slice, encoding: .utf8) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: codingPath,
                      debugDescription: "Invalid UTF-8 string data")
            )
        }
        
        return str
    }
    
    func readUInt32() throws -> UInt32 {
        let size = 4
        let offset = storage.offset
        let d = storage.data
        
        guard offset + size <= d.count else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: codingPath,
                      debugDescription: "Unexpected end of data while reading UInt32")
            )
        }
        
        let b0 = UInt32(d[offset])
        let b1 = UInt32(d[offset + 1]) << 8
        let b2 = UInt32(d[offset + 2]) << 16
        let b3 = UInt32(d[offset + 3]) << 24
        storage.advanceOffset(size)
        return b0 | b1 | b2 | b3
    }
    
    // Read any FixedWidthInteger that was encoded as Int64 on the wire.
    // Throws instead of trapping on overflow/out-of-range.
    func readFixedWidthInteger<I: FixedWidthInteger>(_ type: I.Type) throws -> I {
        let v64 = try readInt64()
        
        if I.isSigned {
            // For signed types, check if min/max fit in Int64 before converting
            // This is safe because all signed integer types have ranges that fit in Int64
            let minV = Int64(I.min)
            let maxV = Int64(I.max)
            guard v64 >= minV, v64 <= maxV else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: codingPath,
                          debugDescription: "\(I.self) out of range: \(v64)")
                )
            }
            return I(v64)
        } else {
            // For unsigned types, I.max might be larger than Int64.max (e.g., UInt.max on 64-bit)
            // So we need to check if I.max fits in Int64 first to avoid overflow
            guard v64 >= 0 else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: codingPath,
                          debugDescription: "\(I.self) out of range: \(v64)")
                )
            }
            // Check if I.max can be represented as Int64 without overflow
            // Compare as UInt64 to avoid overflow during comparison
            if UInt64(I.max) <= UInt64(Int64.max) {
                // Safe to convert I.max to Int64 for comparison
                guard v64 <= Int64(I.max) else {
                    throw DecodingError.dataCorrupted(
                        .init(codingPath: codingPath,
                              debugDescription: "\(I.self) out of range: \(v64)")
                    )
                }
            } else {
                // For types where max > Int64.max (like UInt on 64-bit), 
                // we can only decode values that fit in Int64
                // (values > Int64.max would have been truncated during encoding)
                // v64 is already constrained to Int64 range, so this is fine
            }
            return I(v64)
        }
    }
    
}

// MARK: - Keyed container

fileprivate struct BinaryKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol, Sendable {
    typealias Key = Key
    
    let decoder: _BinaryDecoder
    private var storage: DecoderStorage { decoder.storage }
    
    struct Entry {
        let key: Key
        let valueOffset: Int   // start of the presence flag for this value
        let valueLength: Int   // length of the value payload in bytes
    }
    
    private let entries: [Entry]
    
    var codingPath: [CodingKey] {
        get { storage.codingPath }
        set { storage.setCodingPath(newValue) }
    }
    
    /// All keys present in this keyed container.
    var allKeys: [Key] {
        entries.map { $0.key }
    }
    
    init(decoder: _BinaryDecoder) throws {
        self.decoder = decoder
        
        // Read keyCount (UInt32)
        let countUInt32 = try decoder.readUInt32()
        let count = Int(countUInt32)
        
        var tmpEntries: [Entry] = []
        tmpEntries.reserveCapacity(count)
        
        for _ in 0..<count {
            // 1) key name (String)
            let keyName = try decoder.readString()
            
            // 2) value length (UInt32)
            let valueLengthUInt32 = try decoder.readUInt32()
            let valueLength = Int(valueLengthUInt32)
            
            let valueOffset = decoder.storage.offset
            
            // 3) skip the value bytes so that when init returns,
            //    the decoder offset is at the end of this container.
            decoder.storage.advanceOffset(valueLength)
            
            // Convert to CodingKey if possible; unknown keys are ignored (like JSONDecoder).
            if let codingKey = Key(stringValue: keyName) {
                tmpEntries.append(Entry(key: codingKey,
                                        valueOffset: valueOffset,
                                        valueLength: valueLength))
            }
        }
        
        self.entries = tmpEntries
    }
    
    // MARK: - Helpers
    
    private func entry(for key: Key) -> Entry? {
        entries.first { $0.key.stringValue == key.stringValue }
    }
    
    private func withValue<T>(for key: Key, _ body: () throws -> T) throws -> T {
        guard let entry = entry(for: key) else {
            throw DecodingError.keyNotFound(
                key,
                .init(codingPath: codingPath,
                      debugDescription: "No value associated with key \(key.stringValue)")
            )
        }
        
        let savedOffset = storage.offset
        storage.setOffset(entry.valueOffset)
        defer { storage.setOffset(savedOffset) }
        
        return try body()
    }
    
    // MARK: - Key presence
    
    func contains(_ key: Key) -> Bool {
        entry(for: key) != nil
    }
    
    // MARK: - Data / UUID
    
    func decode(_ type: Data.Type, forKey key: Key) throws -> Data {
        try withValue(for: key) {
            let present = try decoder.readBool()
            guard present else {
                throw DecodingError.valueNotFound(
                    Data.self,
                    .init(codingPath: codingPath + [key],
                          debugDescription: "Expected Data but found nil")
                )
            }
            return try decoder.readData()
        }
    }
    
    func decode(_ type: UUID.Type, forKey key: Key) throws -> UUID {
        try withValue(for: key) {
            let present = try decoder.readBool()
            guard present else {
                throw DecodingError.valueNotFound(
                    UUID.self,
                    .init(codingPath: codingPath + [key],
                          debugDescription: "Expected UUID but found nil")
                )
            }
            return try decoder.readUUID()
        }
    }
    
    func decodeIfPresent(_ type: Data.Type, forKey key: Key) throws -> Data? {
        guard entry(for: key) != nil else { return nil }
        return try withValue(for: key) {
            let present = try decoder.readBool()
            guard present else { return nil }
            return try decoder.readData()
        }
    }
    
    func decodeIfPresent(_ type: UUID.Type, forKey key: Key) throws -> UUID? {
        guard entry(for: key) != nil else { return nil }
        return try withValue(for: key) {
            let present = try decoder.readBool()
            guard present else { return nil }
            return try decoder.readUUID()
        }
    }
    
    // MARK: - Nil / presence
    
    func decodeNil(forKey key: Key) throws -> Bool {
        guard entry(for: key) != nil else { return true } // treat missing as nil
        return try withValue(for: key) {
            let present = try decoder.readBool()
            return !present
        }
    }
    
    // MARK: - Concrete primitives
    
    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
        try withValue(for: key) {
            let present = try decoder.readBool()
            guard present else {
                throw DecodingError.valueNotFound(
                    Bool.self,
                    .init(codingPath: codingPath + [key],
                          debugDescription: "Expected Bool but found nil")
                )
            }
            return try decoder.readBool()
        }
    }
    
    func decode(_ type: String.Type, forKey key: Key) throws -> String {
        try withValue(for: key) {
            let present = try decoder.readBool()
            guard present else {
                throw DecodingError.valueNotFound(
                    String.self,
                    .init(codingPath: codingPath + [key],
                          debugDescription: "Expected String but found nil")
                )
            }
            return try decoder.readString()
        }
    }
    
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
        try withValue(for: key) {
            let present = try decoder.readBool()
            guard present else {
                throw DecodingError.valueNotFound(
                    Double.self,
                    .init(codingPath: codingPath + [key],
                          debugDescription: "Expected Double but found nil")
                )
            }
            return try decoder.readDouble()
        }
    }
    
    func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
        try withValue(for: key) {
            let present = try decoder.readBool()
            guard present else {
                throw DecodingError.valueNotFound(
                    Int.self,
                    .init(codingPath: codingPath + [key],
                          debugDescription: "Expected Int but found nil")
                )
            }
            return Int(try decoder.readInt64())
        }
    }
    
    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
        try withValue(for: key) {
            let present = try decoder.readBool()
            guard present else {
                throw DecodingError.valueNotFound(
                    Int8.self, .init(codingPath: codingPath + [key],
                                     debugDescription: "Expected Int8 but found nil")
                )
            }
            return try decoder.readFixedWidthInteger(Int8.self)
        }
    }
    
    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
        try withValue(for: key) {
            let present = try decoder.readBool()
            guard present else {
                throw DecodingError.valueNotFound(
                    Int16.self, .init(codingPath: codingPath + [key],
                                      debugDescription: "Expected Int16 but found nil")
                )
            }
            return try decoder.readFixedWidthInteger(Int16.self)
        }
    }
    
    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
        try withValue(for: key) {
            let present = try decoder.readBool()
            guard present else {
                throw DecodingError.valueNotFound(
                    Int32.self, .init(codingPath: codingPath + [key],
                                      debugDescription: "Expected Int32 but found nil")
                )
            }
            return try decoder.readFixedWidthInteger(Int32.self)
        }
    }
    
    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
        try withValue(for: key) {
            let present = try decoder.readBool()
            guard present else {
                throw DecodingError.valueNotFound(
                    Int64.self,
                    .init(codingPath: codingPath + [key],
                          debugDescription: "Expected Int64 but found nil")
                )
            }
            return try decoder.readInt64()
        }
    }
    
    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
        try withValue(for: key) {
            let present = try decoder.readBool()
            guard present else {
                throw DecodingError.valueNotFound(
                    UInt.self, .init(codingPath: codingPath + [key],
                                     debugDescription: "Expected UInt but found nil")
                )
            }
            return try decoder.readFixedWidthInteger(UInt.self)
        }
    }
    
    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
        try withValue(for: key) {
            let present = try decoder.readBool()
            guard present else {
                throw DecodingError.valueNotFound(
                    UInt8.self, .init(codingPath: codingPath + [key],
                                      debugDescription: "Expected UInt8 but found nil")
                )
            }
            return try decoder.readFixedWidthInteger(UInt8.self)
        }
    }
    
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
        try withValue(for: key) {
            let present = try decoder.readBool()
            guard present else {
                throw DecodingError.valueNotFound(
                    UInt16.self, .init(codingPath: codingPath + [key],
                                       debugDescription: "Expected UInt16 but found nil")
                )
            }
            return try decoder.readFixedWidthInteger(UInt16.self)
        }
    }
    
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
        try withValue(for: key) {
            let present = try decoder.readBool()
            guard present else {
                throw DecodingError.valueNotFound(
                    UInt32.self, .init(codingPath: codingPath + [key],
                                       debugDescription: "Expected UInt32 but found nil")
                )
            }
            return try decoder.readFixedWidthInteger(UInt32.self)
        }
    }
    
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
        try withValue(for: key) {
            let present = try decoder.readBool()
            guard present else {
                throw DecodingError.valueNotFound(
                    UInt64.self, .init(codingPath: codingPath + [key],
                                       debugDescription: "Expected UInt64 but found nil")
                )
            }
            // Use native UInt64 for version 2+, otherwise use Int64 conversion
            if storage.version >= 2 {
                return try decoder.readUInt64()
            } else {
                return try decoder.readFixedWidthInteger(UInt64.self)
            }
        }
    }
    
    func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
        try withValue(for: key) {
            let present = try decoder.readBool()
            guard present else {
                throw DecodingError.valueNotFound(
                    Float.self, .init(codingPath: codingPath + [key],
                                      debugDescription: "Expected Float but found nil")
                )
            }
            // Use native Float for version 2+, otherwise use Double conversion
            if storage.version >= 2 {
                return try decoder.readFloat()
            } else {
                return Float(try decoder.readDouble())
            }
        }
    }
    
    // MARK: - Generic Decodable
    
    func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T : Decodable {
        // Fast path for leaf types
        if type == Data.self {
            return try decode(Data.self, forKey: key) as! T
        }
        if type == UUID.self {
            return try decode(UUID.self, forKey: key) as! T
        }
        if type == String.self {
            return try decode(String.self, forKey: key) as! T
        }
        if type == Bool.self {
            return try decode(Bool.self, forKey: key) as! T
        }
        if type == Int.self {
            return try decode(Int.self, forKey: key) as! T
        }
        if type == Int8.self {
            return try decode(Int8.self, forKey: key) as! T
        }
        
        if type == Int16.self {
            return try decode(Int16.self, forKey: key) as! T
        }
        
        if type == Int32.self {
            return try decode(Int32.self, forKey: key) as! T
        }
        
        if type == UInt.self {
            return try decode(UInt.self, forKey: key) as! T
        }
        
        if type == UInt8.self {
            return try decode(UInt8.self, forKey: key) as! T
        }
        
        if type == UInt16.self {
            return try decode(UInt16.self, forKey: key) as! T
        }
        
        if type == UInt32.self {
            return try decode(UInt32.self, forKey: key) as! T
        }
        
        if type == UInt64.self {
            return try decode(UInt64.self, forKey: key) as! T
        }
        
        if type == Float.self {
            return try decode(Float.self, forKey: key) as! T
        }
        
        if type == Int64.self {
            return try decode(Int64.self, forKey: key) as! T
        }
        if type == Double.self {
            return try decode(Double.self, forKey: key) as! T
        }
        
        
        // Structured types: presence flag + nested Decodable.
        return try withValue(for: key) {
            let present = try decoder.readBool()
            
            if let optMeta = T.self as? _OptionalDecodingShim.Type {
                if !present {
                    return optMeta._nilValue() as! T
                }
                
                storage.appendCodingPath(key)
                defer { storage.removeLastKey() }
                
                // presence already consumed, so decode wrapped directly
                return try optMeta._decodeWrapped(from: decoder) as! T
            }
            
            // Non-optional: presence must be true
            guard present else {
                throw DecodingError.valueNotFound(
                    T.self,
                    .init(codingPath: codingPath + [key],
                          debugDescription: "Expected \(T.self) but found nil")
                )
            }
            
            storage.appendCodingPath(key)
            defer { storage.removeLastKey() }
            return try T(from: decoder)
        }
        
    }
    
    func decodeIfPresent<T>(_ type: T.Type, forKey key: Key) throws -> T? where T : Decodable {
        guard entry(for: key) != nil else { return nil }
        
        // Leaf types first
        if type == Data.self {
            return try decodeIfPresent(Data.self, forKey: key) as? T
        }
        if type == UUID.self {
            return try decodeIfPresent(UUID.self, forKey: key) as? T
        }
        if type == String.self {
            return try decodeIfPresent(String.self, forKey: key) as? T
        }
        if type == Bool.self {
            return try decodeIfPresent(Bool.self, forKey: key) as? T
        }
        if type == Int.self {
            return try decodeIfPresent(Int.self, forKey: key) as? T
        }
        if type == Int64.self {
            return try decodeIfPresent(Int64.self, forKey: key) as? T
        }
        if type == Double.self {
            return try decodeIfPresent(Double.self, forKey: key) as? T
        }
        
        // Generic path for structured optionals
        return try withValue(for: key) {
            let present = try decoder.readBool()
            guard present else { return nil }
            
            storage.appendCodingPath(key)
            defer { storage.removeLastKey() }
            return try T(from: decoder)
        }
    }
    
    // MARK: - Nested containers
    
    func nestedContainer<NestedKey>(
        keyedBy type: NestedKey.Type,
        forKey key: Key
    ) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        // Interpret the value for this key as a nested keyed container.
        return try withValue(for: key) {
            storage.appendCodingPath(key)
            defer { storage.removeLastKey() }
            let container = try BinaryKeyedDecodingContainer<NestedKey>(decoder: decoder)
            return KeyedDecodingContainer(container)
        }
    }
    
    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        return try withValue(for: key) {
            storage.appendCodingPath(key)
            defer { storage.removeLastKey() }
            return BinaryUnkeyedDecodingContainer(decoder: decoder)
        }
    }
    
    func superDecoder() throws -> Decoder {
        decoder
    }
    
    func superDecoder(forKey key: Key) throws -> Decoder {
        decoder
    }
}

// MARK: - Single value container

fileprivate struct BinarySingleValueDecodingContainer: SingleValueDecodingContainer, Sendable {
    
    let decoder: _BinaryDecoder
    private var storage: DecoderStorage { decoder.storage }
    
    var codingPath: [CodingKey] {
        get { storage.codingPath }
        set { storage.setCodingPath(newValue) }
    }
    
    init(decoder: _BinaryDecoder) {
        self.decoder = decoder
    }
    
    func decodeNil() -> Bool {
        // Single-value container doesn’t have presence flags in this format.
        // If something is "nil", the outer layer shouldn’t have encoded it as a single value.
        return storage.offset == storage.data.count
    }
    
    // MARK: - Concrete primitives – must mirror encoder
    
    func decode(_ type: Bool.Type) throws -> Bool {
        return try decoder.readBool()
    }
    
    func decode(_ type: String.Type) throws -> String {
        return try decoder.readString()
    }
    
    func decode(_ type: Double.Type) throws -> Double {
        return try decoder.readDouble()
    }
    
    func decode(_ type: Float.Type) throws -> Float {
        // Use native Float for version 2+, otherwise use Double conversion
        if storage.version >= 2 {
            return try decoder.readFloat()
        } else {
            return Float(try decoder.readDouble())
        }
    }
    
    func decode(_ type: Int.Type) throws -> Int {
        return Int(try decoder.readInt64())
    }
    
    func decode(_ type: Int8.Type) throws -> Int8 {
        try decoder.readFixedWidthInteger(Int8.self)
    }
    
    func decode(_ type: Int16.Type) throws -> Int16 {
        try decoder.readFixedWidthInteger(Int16.self)
    }
    
    func decode(_ type: Int32.Type) throws -> Int32 {
        try decoder.readFixedWidthInteger(Int32.self)
    }
    
    func decode(_ type: UInt.Type) throws -> UInt {
        try decoder.readFixedWidthInteger(UInt.self)
    }
    
    func decode(_ type: UInt8.Type) throws -> UInt8 {
        try decoder.readFixedWidthInteger(UInt8.self)
    }
    
    func decode(_ type: UInt16.Type) throws -> UInt16 {
        try decoder.readFixedWidthInteger(UInt16.self)
    }
    
    func decode(_ type: UInt32.Type) throws -> UInt32 {
        try decoder.readFixedWidthInteger(UInt32.self)
    }
    
    func decode(_ type: UInt64.Type) throws -> UInt64 {
        // Use native UInt64 for version 2+, otherwise use Int64 conversion
        if storage.version >= 2 {
            return try decoder.readUInt64()
        } else {
            return try decoder.readFixedWidthInteger(UInt64.self)
        }
    }
    
    func decode(_ type: Int64.Type) throws -> Int64 {
        return try decoder.readInt64()
    }
    
    func decode(_ type: Data.Type) throws -> Data {
        return try decoder.readData()
    }
    
    func decode(_ type: UUID.Type) throws -> UUID {
        return try decoder.readUUID()
    }
    
    // MARK: - Generic Decodable
    
    func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
        
        if type == Data.self {
            return try decode(Data.self) as! T
        }
        if type == UUID.self {
            return try decode(UUID.self) as! T
        }
        if type == String.self {
            return try decode(String.self) as! T
        }
        if type == Bool.self {
            return try decode(Bool.self) as! T
        }
        if type == Int.self {
            return try decode(Int.self) as! T
        }
        if type == Int64.self {
            return try decode(Int64.self) as! T
        }
        if type == Double.self {
            return try decode(Double.self) as! T
        }
        
        // Everything else is a structured type that will request its own
        // keyed/unkeyed/single-value containers as needed.
        return try T(from: decoder)
    }
}

// MARK: - Unkeyed container

fileprivate struct BinaryUnkeyedDecodingContainer: UnkeyedDecodingContainer, Sendable {
    
    let decoder: _BinaryDecoder
    private var storage: DecoderStorage { decoder.storage }
    
    var codingPath: [CodingKey] {
        get { storage.codingPath }
        set { storage.setCodingPath(newValue) }
    }
    
    private(set) var count: Int?
    private(set) var currentIndex: Int = 0
    
    init(decoder: _BinaryDecoder) {
        self.decoder = decoder
        
        // Read the count (UInt32) from the data
        do {
            let countUInt32 = try decoder.readUInt32()
            self.count = Int(countUInt32)
        } catch {
            // If we can't read the count, set to nil
            self.count = nil
        }
    }
    
    var isAtEnd: Bool {
        guard let count = count else { return true }
        return currentIndex >= count
    }
    
    // MARK: - Nil
    
    mutating func decodeNil() throws -> Bool {
        guard count != nil else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: codingPath,
                      debugDescription: "Cannot decode array element: invalid array count")
            )
        }
        
        guard !isAtEnd else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: codingPath,
                      debugDescription: "Unkeyed container is at end")
            )
        }
        
        let present = try decoder.readBool()
        if !present {
            currentIndex += 1
        }
        return !present
    }
    
    // MARK: - Concrete types
    
    mutating func decode(_ type: Bool.Type) throws -> Bool {
        try checkNotAtEnd()
        let present = try decoder.readBool()
        guard present else {
            throw DecodingError.valueNotFound(
                Bool.self,
                .init(codingPath: codingPath + [ArrayIndexKey(currentIndex)],
                      debugDescription: "Expected Bool but found nil")
            )
        }
        let value = try decoder.readBool()
        currentIndex += 1
        return value
    }
    
    mutating func decode(_ type: String.Type) throws -> String {
        try checkNotAtEnd()
        let present = try decoder.readBool()
        guard present else {
            throw DecodingError.valueNotFound(
                String.self,
                .init(codingPath: codingPath + [ArrayIndexKey(currentIndex)],
                      debugDescription: "Expected String but found nil")
            )
        }
        let value = try decoder.readString()
        currentIndex += 1
        return value
    }
    
    mutating func decode(_ type: Double.Type) throws -> Double {
        try checkNotAtEnd()
        let present = try decoder.readBool()
        guard present else {
            throw DecodingError.valueNotFound(
                Double.self,
                .init(codingPath: codingPath + [ArrayIndexKey(currentIndex)],
                      debugDescription: "Expected Double but found nil")
            )
        }
        let value = try decoder.readDouble()
        currentIndex += 1
        return value
    }
    
    mutating func decode(_ type: Int.Type) throws -> Int {
        try checkNotAtEnd()
        let present = try decoder.readBool()
        guard present else {
            throw DecodingError.valueNotFound(
                Int.self,
                .init(codingPath: codingPath + [ArrayIndexKey(currentIndex)],
                      debugDescription: "Expected Int but found nil")
            )
        }
        let value = Int(try decoder.readInt64())
        currentIndex += 1
        return value
    }
    
    mutating func decode(_ type: Int64.Type) throws -> Int64 {
        try checkNotAtEnd()
        let present = try decoder.readBool()
        guard present else {
            throw DecodingError.valueNotFound(
                Int64.self,
                .init(codingPath: codingPath + [ArrayIndexKey(currentIndex)],
                      debugDescription: "Expected Int64 but found nil")
            )
        }
        let value = try decoder.readInt64()
        currentIndex += 1
        return value
    }
    
    mutating func decode(_ type: Data.Type) throws -> Data {
        try checkNotAtEnd()
        let present = try decoder.readBool()
        guard present else {
            throw DecodingError.valueNotFound(
                Data.self,
                .init(codingPath: codingPath + [ArrayIndexKey(currentIndex)],
                      debugDescription: "Expected Data but found nil")
            )
        }
        let value = try decoder.readData()
        currentIndex += 1
        return value
    }
    
    mutating func decode(_ type: UUID.Type) throws -> UUID {
        try checkNotAtEnd()
        let present = try decoder.readBool()
        guard present else {
            throw DecodingError.valueNotFound(
                UUID.self,
                .init(codingPath: codingPath + [ArrayIndexKey(currentIndex)],
                      debugDescription: "Expected UUID but found nil")
            )
        }
        let value = try decoder.readUUID()
        currentIndex += 1
        return value
    }
    
    // MARK: - Generic Decodable
    
    mutating func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
        try checkNotAtEnd()
        let present = try decoder.readBool()
        
        // Handle Optional<Wrapped> specifically
        if let optMeta = T.self as? _OptionalDecodingShim.Type {
            defer { currentIndex += 1 }
            
            if !present {
                // element is nil
                return optMeta._nilValue() as! T
            } else {
                // For optional values in unkeyed containers, decode the wrapped value
                // directly from the unkeyed container context, not from a single-value container
                // The presence flag has already been read, so we decode the value directly
                storage.appendCodingPath(ArrayIndexKey(currentIndex))
                defer { storage.removeLastKey() }
                
                // Get the wrapped type and decode it directly (no presence flag, already read)
                if let wrappedType = (T.self as? _OptionalMarker.Type)?._wrappedType {
                    // Decode the wrapped value directly without reading another presence flag
                    if wrappedType == Int.self {
                        let v = Int(try decoder.readInt64())
                        return (v as? T) ?? optMeta._nilValue() as! T
                    } else if wrappedType == Int8.self {
                        let v: Int8 = try decoder.readFixedWidthInteger(Int8.self)
                        return (v as? T) ?? optMeta._nilValue() as! T
                    } else if wrappedType == Int16.self {
                        let v: Int16 = try decoder.readFixedWidthInteger(Int16.self)
                        return (v as? T) ?? optMeta._nilValue() as! T
                    } else if wrappedType == Int32.self {
                        let v: Int32 = try decoder.readFixedWidthInteger(Int32.self)
                        return (v as? T) ?? optMeta._nilValue() as! T
                    } else if wrappedType == Int64.self {
                        let v = try decoder.readInt64()
                        return (v as? T) ?? optMeta._nilValue() as! T
                    } else if wrappedType == UInt.self {
                        let v: UInt = try decoder.readFixedWidthInteger(UInt.self)
                        return (v as? T) ?? optMeta._nilValue() as! T
                    } else if wrappedType == UInt8.self {
                        let v: UInt8 = try decoder.readFixedWidthInteger(UInt8.self)
                        return (v as? T) ?? optMeta._nilValue() as! T
                    } else if wrappedType == UInt16.self {
                        let v: UInt16 = try decoder.readFixedWidthInteger(UInt16.self)
                        return (v as? T) ?? optMeta._nilValue() as! T
                    } else if wrappedType == UInt32.self {
                        let v: UInt32 = try decoder.readFixedWidthInteger(UInt32.self)
                        return (v as? T) ?? optMeta._nilValue() as! T
                    } else if wrappedType == UInt64.self {
                        let v: UInt64 = storage.version >= 2 
                            ? try decoder.readUInt64() 
                            : try decoder.readFixedWidthInteger(UInt64.self)
                        return (v as? T) ?? optMeta._nilValue() as! T
                    } else if wrappedType == String.self {
                        let v = try decoder.readString()
                        return (v as? T) ?? optMeta._nilValue() as! T
                    } else if wrappedType == Bool.self {
                        let v = try decoder.readBool()
                        return (v as? T) ?? optMeta._nilValue() as! T
                    } else if wrappedType == Double.self {
                        let v = try decoder.readDouble()
                        return (v as? T) ?? optMeta._nilValue() as! T
                    } else if wrappedType == Float.self {
                        let v = storage.version >= 2 
                            ? try decoder.readFloat() 
                            : Float(try decoder.readDouble())
                        return (v as? T) ?? optMeta._nilValue() as! T
                    } else if wrappedType == Data.self {
                        let v = try decoder.readData()
                        return (v as? T) ?? optMeta._nilValue() as! T
                    } else if wrappedType == UUID.self {
                        let v = try decoder.readUUID()
                        return (v as? T) ?? optMeta._nilValue() as! T
                    }
                }
                
                // Fallback to the original method for complex types
                return try optMeta._decodeWrapped(from: decoder) as! T
            }
        }
        
        // Non-optional path: presence must be true
        guard present else {
            throw DecodingError.valueNotFound(
                T.self,
                .init(codingPath: codingPath + [ArrayIndexKey(currentIndex)],
                      debugDescription: "Expected \(T.self) but found nil")
            )
        }
        
        // Special-case same leaf types
        if type == Data.self {
            let v = try decoder.readData()
            currentIndex += 1
            return v as! T
        }
        if type == UUID.self {
            let v = try decoder.readUUID()
            currentIndex += 1
            return v as! T
        }
        if type == String.self {
            let v = try decoder.readString()
            currentIndex += 1
            return v as! T
        }
        if type == Bool.self {
            let v = try decoder.readBool()
            currentIndex += 1
            return v as! T
        }
        if type == Int.self {
            let v = Int(try decoder.readInt64())
            currentIndex += 1
            return v as! T
        }
        if type == Int8.self {
            let v: Int8 = try decoder.readFixedWidthInteger(Int8.self)
            currentIndex += 1
            return v as! T
        }
        if type == Int16.self {
            let v: Int16 = try decoder.readFixedWidthInteger(Int16.self)
            currentIndex += 1
            return v as! T
        }
        if type == Int32.self {
            let v: Int32 = try decoder.readFixedWidthInteger(Int32.self)
            currentIndex += 1
            return v as! T
        }
        if type == UInt.self {
            let v: UInt = try decoder.readFixedWidthInteger(UInt.self)
            currentIndex += 1
            return v as! T
        }
        if type == UInt8.self {
            let v: UInt8 = try decoder.readFixedWidthInteger(UInt8.self)
            currentIndex += 1
            return v as! T
        }
        if type == UInt16.self {
            let v: UInt16 = try decoder.readFixedWidthInteger(UInt16.self)
            currentIndex += 1
            return v as! T
        }
        if type == UInt32.self {
            let v: UInt32 = try decoder.readFixedWidthInteger(UInt32.self)
            currentIndex += 1
            return v as! T
        }
        if type == UInt64.self {
            let v: UInt64 = storage.version >= 2 
                ? try decoder.readUInt64() 
                : try decoder.readFixedWidthInteger(UInt64.self)
            currentIndex += 1
            return v as! T
        }
        if type == Float.self {
            let v = storage.version >= 2 
                ? try decoder.readFloat() 
                : Float(try decoder.readDouble())
            currentIndex += 1
            return v as! T
        }
        
        if type == Int64.self {
            let v = try decoder.readInt64()
            currentIndex += 1
            return v as! T
        }
        if type == Double.self {
            let v = try decoder.readDouble()
            currentIndex += 1
            return v as! T
        }
        
        // Fallback: structured types
        storage.appendCodingPath(ArrayIndexKey(currentIndex))
        defer { storage.removeLastKey() }
        let value = try T(from: decoder)
        currentIndex += 1
        return value
    }
    
    // MARK: - Nested containers
    
    mutating func nestedContainer<NestedKey>(
        keyedBy type: NestedKey.Type
    ) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        try checkNotAtEnd()
        let present = try decoder.readBool()
        guard present else {
            throw DecodingError.valueNotFound(
                KeyedDecodingContainer<NestedKey>.self,
                .init(codingPath: codingPath + [ArrayIndexKey(currentIndex)],
                      debugDescription: "Expected nested container but found nil")
            )
        }
        
        storage.appendCodingPath(ArrayIndexKey(currentIndex))
        defer { storage.removeLastKey() }
        
        let container = try BinaryKeyedDecodingContainer<NestedKey>(decoder: decoder)
        currentIndex += 1
        return KeyedDecodingContainer(container)
    }
    
    mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
        try checkNotAtEnd()
        let present = try decoder.readBool()
        guard present else {
            throw DecodingError.valueNotFound(
                UnkeyedDecodingContainer.self,
                .init(codingPath: codingPath + [ArrayIndexKey(currentIndex)],
                      debugDescription: "Expected nested unkeyed container but found nil")
            )
        }
        
        storage.appendCodingPath(ArrayIndexKey(currentIndex))
        defer { storage.removeLastKey() }
        
        let container = BinaryUnkeyedDecodingContainer(decoder: decoder)
        currentIndex += 1
        return container
    }
    
    mutating func superDecoder() throws -> Decoder {
        decoder
    }
    
    // MARK: - Helper
    
    private func checkNotAtEnd() throws {
        guard count != nil else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: codingPath,
                      debugDescription: "Cannot decode array element: invalid array count")
            )
        }
        
        guard !isAtEnd else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: codingPath,
                      debugDescription: "Unkeyed container is at end")
            )
        }
    }
}

// Helper struct for array index coding keys
fileprivate struct ArrayIndexKey: CodingKey, Sendable {
    var stringValue: String {
        return "\(intValue ?? -1)"
    }
    
    var intValue: Int?
    
    init(_ intValue: Int) {
        self.intValue = intValue
    }
    
    init?(stringValue: String) {
        guard let intValue = Int(stringValue) else { return nil }
        self.intValue = intValue
    }
    
    init?(intValue: Int) {
        self.intValue = intValue
    }
}

// Binary Format Specification:
// Endianness: Little
// Layout:
// - Bool:    1 byte (0 or 1)
// - Int64:   8 bytes, little-endian
// - Double:  8 bytes, IEEE754, little-endian
// - UUID:    16 raw bytes
// - Data:    UInt32 length (LE) + raw bytes
// - String:  UInt32 length (LE) + UTF-8 bytes
// - Field:   1-byte presence flag, then value if present
// - Array:   UInt32 count (LE) + [presence flag + value] for each element

// MARK: - Optional shims

protocol _OptionalEncodingShim {
    var _isNil: Bool { get }
    func _encodeWrapped(to encoder: Encoder) throws
}

extension Optional: _OptionalEncodingShim where Wrapped: Encodable {
    var _isNil: Bool { self == nil }
    
    func _encodeWrapped(to encoder: Encoder) throws {
        guard let wrapped = self else { return }
        try wrapped.encode(to: encoder)
    }
}

fileprivate protocol _OptionalDecodingShim {
    static func _nilValue() -> Self
    static func _decodeWrapped(from decoder: _BinaryDecoder) throws -> Self
}

extension Optional: _OptionalDecodingShim where Wrapped: Decodable {
    static func _nilValue() -> Optional<Wrapped> { .none }
    
    fileprivate static func _decodeWrapped(from decoder: _BinaryDecoder) throws -> Optional<Wrapped> {
        let wrapped = try Wrapped(from: decoder)
        return .some(wrapped)
    }
}

// MARK: - Canonical type descriptors (for header matching)

fileprivate enum TypeCategory: Sendable {
    case primitiveOrStd    // Int, String, Array<...>, Set<...>, Dictionary<...>, Data, UUID, etc.
    case custom            // Your own types like AuthPacket, ChannelInfo, etc.
}

fileprivate struct CanonicalTypeDescriptor: Equatable, Sendable {
    let coreName: String   // module-stripped, container+generics kept (e.g. "Array<Swift.String>")
    let isOptional: Bool
    let category: TypeCategory
}

fileprivate protocol _OptionalMarker {
    static var _wrappedType: Any.Type { get }
}

extension Optional: _OptionalMarker {
    static var _wrappedType: Any.Type { Wrapped.self }
}

/// Compute a "core" name from a fully qualified type string.
///
/// Non-generic types:
///   "BinaryCodableTests.IRC.AuthPacket"  -> "AuthPacket"
///   "NeedleTailIRC.AuthPacket"          -> "AuthPacket"
///
/// Generic types:
///   "Swift.Array<Swift.String>"         -> "Array<Swift.String>"
///   "Swift.Set<Swift.String>"           -> "Set<Swift.String>"
///   "Swift.Dictionary<Swift.String,Swift.Int>" -> "Dictionary<Swift.String,Swift.Int>"
///
/// Other generic types:
///   "MyMod.Foo<Other.Bar.Baz>"          -> "Foo<Other.Bar.Baz>"
fileprivate func canonicalCoreNameString(_ full: String) -> String {
    // Generic case
    if let angleIndex = full.firstIndex(of: "<") {
        let prefixPart = String(full[..<angleIndex])   // e.g. "Swift.Array"
        let genericsPart = String(full[angleIndex...]) // e.g. "<Swift.String>"
        
        let simpleContainer: String
        if prefixPart.hasSuffix("Array") {
            simpleContainer = "Array"
        } else if prefixPart.hasSuffix("Set") {
            simpleContainer = "Set"
        } else if prefixPart.hasSuffix("Dictionary") {
            simpleContainer = "Dictionary"
        } else {
            // Unknown generic: just take last path component
            let last = prefixPart.split(separator: ".").last ?? Substring(prefixPart)
            simpleContainer = String(last)
        }
        
        return "\(simpleContainer)\(genericsPart)"
    }
    
    // Non-generic: keep simple name (last component)
    if let last = full.split(separator: ".").last {
        return String(last)
    }
    return full
}

fileprivate func isPrimitiveOrStdCoreName(_ coreName: String) -> Bool {
    // Basic primitives
    let primitives: Set<String> = [
        "Int", "Int8", "Int16", "Int32", "Int64",
        "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
        "String", "Bool", "Double", "Float",
        "Data", "UUID"
    ]
    
    if primitives.contains(coreName) {
        return true
    }
    
    // Standard containers
    if coreName.hasPrefix("Array<") { return true }
    if coreName.hasPrefix("Set<") { return true }
    if coreName.hasPrefix("Dictionary<") { return true }
    
    return false
}

/// Canonical descriptor for a Swift type `T`
/// - Strips Optional (but records it as `isOptional`)
/// - Reduces fully qualified name to a "core" name (module-agnostic)
/// - Categorizes as primitive/std vs custom
fileprivate func descriptor(for type: Any.Type) -> CanonicalTypeDescriptor {
    let isOpt: Bool
    let underlying: Any.Type
    
    if let opt = type as? _OptionalMarker.Type {
        isOpt = true
        underlying = opt._wrappedType
    } else {
        isOpt = false
        underlying = type
    }
    
    let full = String(reflecting: underlying)
    let core = canonicalCoreNameString(full)
    let category: TypeCategory = isPrimitiveOrStdCoreName(core) ? .primitiveOrStd : .custom
    
    return CanonicalTypeDescriptor(coreName: core, isOptional: isOpt, category: category)
}

/// Canonical descriptor parsed from the encoded type-name header.
/// Handles Optional wrappers and reduces inner type string to the same
/// core-name format as `descriptor(for:)`.
fileprivate func descriptor(fromEncodedName name: String) -> CanonicalTypeDescriptor {
    let swiftOptPrefix = "Swift.Optional<"
    let plainOptPrefix = "Optional<"
    let optSuffix      = ">"
    
    let isOpt: Bool
    let innerRaw: String
    
    if name.hasPrefix(swiftOptPrefix), name.hasSuffix(optSuffix) {
        isOpt = true
        innerRaw = String(name.dropFirst(swiftOptPrefix.count).dropLast(optSuffix.count))
    } else if name.hasPrefix(plainOptPrefix), name.hasSuffix(optSuffix) {
        isOpt = true
        innerRaw = String(name.dropFirst(plainOptPrefix.count).dropLast(optSuffix.count))
    } else {
        isOpt = false
        innerRaw = name
    }
    
    let core = canonicalCoreNameString(innerRaw)
    let category: TypeCategory = isPrimitiveOrStdCoreName(core) ? .primitiveOrStd : .custom
    
    return CanonicalTypeDescriptor(coreName: core, isOptional: isOpt, category: category)
}

/// Our compatibility rule:
/// - `coreName` must match (so Set<String> vs Array<String> is always a mismatch)
/// - if both `.custom`, we ignore `isOptional`
///   -> Optional<AuthPacket> <-> AuthPacket OK
///   -> IRC.AuthPacket <-> Server.AuthPacket OK
/// - otherwise (primitives / std containers), `isOptional` must match
///   -> Int? -> Int is NOT OK
fileprivate func areCompatible(_ encoded: CanonicalTypeDescriptor,
                               _ requested: CanonicalTypeDescriptor) -> Bool {
    guard encoded.coreName == requested.coreName else { return false }
    
    switch (encoded.category, requested.category) {
    case (.custom, .custom):
        // Custom model types: allow Optional vs non-Optional
        return true
    default:
        // Primitives / std containers: Optional must match
        return encoded.isOptional == requested.isOptional
    }
}
