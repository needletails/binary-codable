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

// Public entry point
public struct BinaryDecoder: Sendable {
    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        // Special case for Data: just read it using our raw format
        if type == Data.self {
            let storage = DecoderStorage(data: data)
            let core = _BinaryDecoder(storage: storage)
            let result = try core.readData()
            return result as! T
        }
        
        let storage = DecoderStorage(data: data)
        let core = _BinaryDecoder(storage: storage)
        return try T(from: core)
    }
}


// The shared state (single cursor)
fileprivate final class DecoderStorage: @unchecked Sendable {
    private(set) var data: Data
    private(set) var offset: Int
    private(set) var codingPath: [CodingKey]
    
    init(data: Data, offset: Int = 0, codingPath: [CodingKey] = []) {
        self.data = data
        self.offset = offset
        self.codingPath = codingPath
    }
    
    func advanceOffset(_ offset: Int) {
        self.offset += offset
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

// Internal backing decoder
fileprivate struct _BinaryDecoder: Decoder, @unchecked Sendable {
    
    let storage: DecoderStorage
    
    var codingPath: [CodingKey] {
        get { storage.codingPath }
        set { storage.setCodingPath(newValue) }
    }
    
    var userInfo: [CodingUserInfoKey : Any] = [:]
    
    // MARK: - Required container methods
    
    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key: CodingKey {
        let container = BinaryKeyedDecodingContainer<Key>(decoder: self)
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
        let value = b0 | b1 | b2 | b3

        storage.advanceOffset(size)
        return value
    }

}

fileprivate struct BinaryKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol, Sendable {
    
    typealias Key = Key
    
    let decoder: _BinaryDecoder
    
    // Share codingPath with the storage instead of keeping a copy.
    private var storage: DecoderStorage { decoder.storage }
    
    var codingPath: [CodingKey] {
        get { storage.codingPath }
        set { storage.setCodingPath(newValue) }
    }
    
    // We don't track keys on the wire; this is mostly for error reporting / introspection.
    var allKeys: [Key] = []
    
    init(decoder: _BinaryDecoder) {
        self.decoder = decoder
    }
    
    func contains(_ key: Key) -> Bool {
        // Format uses presence flags, not per-key metadata.
        true
    }
    
    // MARK: - Data / UUID
    
    func decode(_ type: Data.Type, forKey key: Key) throws -> Data {
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
    
    func decode(_ type: UUID.Type, forKey key: Key) throws -> UUID {
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
    
    func decodeIfPresent(_ type: Data.Type, forKey key: Key) throws -> Data? {
        let present = try decoder.readBool()
        guard present else { return nil }
        return try decoder.readData()
    }
    
    func decodeIfPresent(_ type: UUID.Type, forKey key: Key) throws -> UUID? {
        let present = try decoder.readBool()
        guard present else { return nil }
        return try decoder.readUUID()
    }
    
    // MARK: - Nil / presence
    
    func decodeNil(forKey key: Key) throws -> Bool {
        let present = try decoder.readBool()
        return !present
    }
    
    // MARK: - Concrete primitives
    
    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
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
    
    func decode(_ type: String.Type, forKey key: Key) throws -> String {
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
    
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
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
    
    func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
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
    
    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
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
    
    // MARK: - Generic Decodable
    
    func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T : Decodable {
        // presence flag is always there
        let present = try decoder.readBool()
        guard present else {
            throw DecodingError.valueNotFound(
                T.self,
                .init(codingPath: codingPath + [key],
                      debugDescription: "Expected \(T.self) but found nil")
            )
        }

        // Special-case same leaf types as in the encoder:
        if type == Data.self {
            let value = try decoder.readData()
            return value as! T
        }
        if type == UUID.self {
            let value = try decoder.readUUID()
            return value as! T
        }
        if type == String.self {
            let value = try decoder.readString()
            return value as! T
        }
        if type == Bool.self {
            let value = try decoder.readBool()
            return value as! T
        }
        if type == Int.self {
            let value = Int(try decoder.readInt64())
            return value as! T
        }
        if type == Int64.self {
            let value = try decoder.readInt64()
            return value as! T
        }
        if type == Double.self {
            let value = try decoder.readDouble()
            return value as! T
        }

        // Structured types: let them decode themselves.
        storage.appendCodingPath(key)
        defer { storage.removeLastKey() }
        return try T(from: decoder)
    }

    
    // MARK: - Optional Decodable
    
    func decodeIfPresent(_ type: Bool.Type, forKey key: Key) throws -> Bool? {
        let present = try decoder.readBool()
        guard present else { return nil }
        return try decoder.readBool()
    }
    
    func decodeIfPresent(_ type: String.Type, forKey key: Key) throws -> String? {
        let present = try decoder.readBool()
        guard present else { return nil }
        return try decoder.readString()
    }
    
    func decodeIfPresent(_ type: Double.Type, forKey key: Key) throws -> Double? {
        let present = try decoder.readBool()
        guard present else { return nil }
        return try decoder.readDouble()
    }
    
    func decodeIfPresent(_ type: Int.Type, forKey key: Key) throws -> Int? {
        let present = try decoder.readBool()
        guard present else { return nil }
        return Int(try decoder.readInt64())
    }
    
    func decodeIfPresent(_ type: Int64.Type, forKey key: Key) throws -> Int64? {
        let present = try decoder.readBool()
        guard present else { return nil }
        return try decoder.readInt64()
    }
    
    func decodeIfPresent<T>(_ type: T.Type, forKey key: Key) throws -> T? where T: Decodable {
        // Route primitive/leaf types to their concrete overloads
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
        let present = try decoder.readBool()
        guard present else { return nil }

        storage.appendCodingPath(key)
        defer { storage.removeLastKey() }
        return try T(from: decoder)
    }


    
    // MARK: - Nested containers
    
    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type,
                                    forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        // Nested containers don't read their own presence flag - it's already handled
        // by the generic decode<T> method or the field's presence flag
        storage.appendCodingPath(key)
        defer { storage.removeLastKey() }
        
        // Create a new keyed container for the nested object
        let container = BinaryKeyedDecodingContainer<NestedKey>(decoder: decoder)
        return KeyedDecodingContainer(container)
    }
    
    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        // Nested containers don't read their own presence flag - it's already handled
        // by the generic decode<T> method or the field's presence flag
        storage.appendCodingPath(key)
        defer { storage.removeLastKey() }
        
        // Create a new unkeyed container for the nested array
        return BinaryUnkeyedDecodingContainer(decoder: decoder)
    }
    
    func superDecoder() throws -> Decoder {
        decoder
    }
    
    func superDecoder(forKey key: Key) throws -> Decoder {
        decoder
    }
}


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
    
    func decode(_ type: Int.Type) throws -> Int {
        return Int(try decoder.readInt64())
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
                storage.appendCodingPath(ArrayIndexKey(currentIndex))
                defer { storage.removeLastKey() }
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
    
    mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
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
        
        let container = BinaryKeyedDecodingContainer<NestedKey>(decoder: decoder)
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
fileprivate struct ArrayIndexKey: CodingKey {
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
