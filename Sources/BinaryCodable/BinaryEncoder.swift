//
//  BinaryEncoder.swift
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

public struct BinaryEncoder {
    public func encode(_ value: Data) throws -> Data {
        let storage = EncoderStorage()
        storage.write(value)
        return storage.data
    }
    
    public func encode<T: Encodable>(_ value: T) throws -> Data {
        let storage = EncoderStorage()
        let core = _BinaryEncoder(storage: storage)
        try value.encode(to: core)
        return storage.data
    }
}

fileprivate final class EncoderStorage: @unchecked Sendable {
    
    private(set) var data: Data
    private(set) var codingPath: [CodingKey]
    
    init(codingPath: [CodingKey] = []) {
        self.data = Data()
        self.codingPath = codingPath
    }
    
    func setCodingPath(_ path: [CodingKey]) {
        codingPath = path
    }
    
    func appendCodingPath(_ key: CodingKey) {
        codingPath.append(key)
    }
    
    func removeLastCodingKey() {
        codingPath.removeLast()
    }
    
    func replaceCount(at position: Int, with count: UInt32) {
        let byteCount = MemoryLayout<UInt32>.size
        precondition(position + byteCount <= data.count,
                     "Count patch position out of bounds")
        
        var le = count.littleEndian
        let bytes = withUnsafeBytes(of: &le) { Array($0) } // [UInt8]
        data.replaceSubrange(position ..< position + byteCount, with: bytes)
    }
    
    // Low-level writers; these must match your decoder
    
    func write(_ value: Bool) {
        data.append(value ? 1 : 0)
    }
    
    func writePresence(_ isPresent: Bool) {
        data.append(isPresent ? 1 : 0)
    }
    
    func write(_ value: Int64) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }
    
    func write(_ value: Double) {
        var bits = value.bitPattern.littleEndian
        withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
    }
    
    func write(_ value: UInt32) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }
    
    func write(_ value: String) {
        let utf8 = value.utf8
        write(UInt32(utf8.count))
        data.append(contentsOf: utf8)
    }
    
    func write(_ value: Data) {
        write(UInt32(value.count))
        data.append(value)
    }
    
    func write(_ uuid: UUID) {
        var u = uuid.uuid
        withUnsafeBytes(of: &u) { data.append(contentsOf: $0) }
    }
}


// Internal implementation
fileprivate struct _BinaryEncoder: Encoder, @unchecked Sendable {
    
    let storage: EncoderStorage
    
    var codingPath: [CodingKey] {
        get { storage.codingPath }
        set { storage.setCodingPath(newValue) }
    }
    
    var userInfo: [CodingUserInfoKey : Any] = [:]
    
    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key : CodingKey {
        let container = BinaryKeyedEncodingContainer<Key>(encoder: self)
        return KeyedEncodingContainer(container)
    }
    
    func unkeyedContainer() -> any UnkeyedEncodingContainer {
        // For now you can throw, or implement later.
        BinaryUnkeyedEncodingContainer(encoder: self)
    }
    
    func singleValueContainer() -> any SingleValueEncodingContainer {
        BinarySingleValueEncodingContainer(encoder: self)
    }
    
    // Convenience passthroughs if you want direct use from containers:
    func writePresence(_ isPresent: Bool) {
        storage.writePresence(isPresent)
    }
    
    func write(_ value: Bool) {
        storage.write(value)
    }
    
    func write(_ value: Int64) {
        storage.write(value)
    }
    
    func write(_ value: Double) {
        storage.write(value)
    }
    
    func write(_ value: String) {
        storage.write(value)
    }
    
    func write(_ value: Data) {
        storage.write(value)
    }
    
    func write(_ value: UUID) {
        storage.write(value)
    }
}


// MARK: - Keyed Encoding Container

fileprivate struct BinaryKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol, Sendable {
    typealias Key = Key
    
    let encoder: _BinaryEncoder
    private var storage: EncoderStorage { encoder.storage }
    
    var codingPath: [CodingKey] {
        get { storage.codingPath }
        set { storage.setCodingPath(newValue) }
    }
    
    init(encoder: _BinaryEncoder) {
        self.encoder = encoder
    }
    
    // MARK: - Nil / presence
    
    mutating func encodeNil(forKey key: Key) throws {
        storage.writePresence(false)
    }
    
    // MARK: - Concrete types
    
    mutating func encode(_ value: Bool, forKey key: Key) throws {
        storage.writePresence(true)
        storage.write(value)
    }
    
    mutating func encode(_ value: String, forKey key: Key) throws {
        storage.writePresence(true)
        storage.write(value)
    }
    
    mutating func encode(_ value: Double, forKey key: Key) throws {
        storage.writePresence(true)
        storage.write(value)
    }
    
    mutating func encode(_ value: Int, forKey key: Key) throws {
        storage.writePresence(true)
        storage.write(Int64(value))
    }
    
    mutating func encode(_ value: Int64, forKey key: Key) throws {
        storage.writePresence(true)
        storage.write(value)
    }
    
    mutating func encode(_ value: Data, forKey key: Key) throws {
        storage.writePresence(true)
        storage.write(value)
    }
    
    mutating func encode(_ value: UUID, forKey key: Key) throws {
        storage.writePresence(true)
        storage.write(value)
    }
    
    // MARK: - Generic Encodable
    
    mutating func encode<T>(_ value: T, forKey key: Key) throws where T : Encodable {
        // 🔑 Handle leaf / primitive types here so they *don’t* go through T.encode(to:)
        if let data = value as? Data {
            try encode(data, forKey: key)      // uses your concrete Data encoder (presence + length+bytes)
            return
        }
        if let uuid = value as? UUID {
            try encode(uuid, forKey: key)
            return
        }
        if let string = value as? String {
            try encode(string, forKey: key)
            return
        }
        if let bool = value as? Bool {
            try encode(bool, forKey: key)
            return
        }
        if let int = value as? Int {
            try encode(int, forKey: key)
            return
        }
        if let int64 = value as? Int64 {
            try encode(int64, forKey: key)
            return
        }
        if let double = value as? Double {
            try encode(double, forKey: key)
            return
        }
        
        // Fallback: structured types (your own structs/enums) can drive encoding.
        storage.writePresence(true)
        storage.appendCodingPath(key)
        defer { storage.removeLastCodingKey() }
        try value.encode(to: encoder)
    }
    
    // MARK: - Optionals
    
    mutating func encodeIfPresent(_ value: Bool?, forKey key: Key) throws {
        guard let value else {
            try encodeNil(forKey: key); return
        }
        try encode(value, forKey: key)
    }
    
    mutating func encodeIfPresent(_ value: String?, forKey key: Key) throws {
        guard let value else {
            try encodeNil(forKey: key); return
        }
        try encode(value, forKey: key)
    }
    
    mutating func encodeIfPresent(_ value: Double?, forKey key: Key) throws {
        guard let value else {
            try encodeNil(forKey: key); return
        }
        try encode(value, forKey: key)
    }
    
    mutating func encodeIfPresent(_ value: Int?, forKey key: Key) throws {
        guard let value else {
            try encodeNil(forKey: key); return
        }
        try encode(value, forKey: key)
    }
    
    mutating func encodeIfPresent(_ value: Int64?, forKey key: Key) throws {
        guard let value else {
            try encodeNil(forKey: key); return
        }
        try encode(value, forKey: key)
    }
    
    mutating func encodeIfPresent(_ value: Data?, forKey key: Key) throws {
        guard let value else {
            try encodeNil(forKey: key); return
        }
        try encode(value, forKey: key)
    }
    
    mutating func encodeIfPresent(_ value: UUID?, forKey key: Key) throws {
        guard let value else {
            try encodeNil(forKey: key); return
        }
        try encode(value, forKey: key)
    }
    
    mutating func encodeIfPresent<T>(_ value: T?, forKey key: Key) throws where T : Encodable {
        guard let value else {
            try encodeNil(forKey: key); return
        }
        try encode(value, forKey: key)
    }
    
    // MARK: - Nested containers
    
    mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type,
                                             forKey key: Key) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
        // Nested containers don't write their own presence flag - it's already handled
        // by the generic encode<T> method or the field's presence flag
        storage.appendCodingPath(key)
        defer { storage.removeLastCodingKey() }
        let nested = BinaryKeyedEncodingContainer<NestedKey>(encoder: encoder)
        return KeyedEncodingContainer(nested)
    }
    
    mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
        // Nested containers don't write their own presence flag - it's already handled
        // by the generic encode<T> method or the field's presence flag
        storage.appendCodingPath(key)
        defer { storage.removeLastCodingKey() }
        return BinaryUnkeyedEncodingContainer(encoder: encoder)
    }
    
    mutating func superEncoder() -> Encoder {
        encoder
    }
    
    mutating func superEncoder(forKey key: Key) -> Encoder {
        encoder
    }
}


// MARK: - Unkeyed container

fileprivate struct BinaryUnkeyedEncodingContainer: UnkeyedEncodingContainer {
    let encoder: _BinaryEncoder
    
    private var storage: EncoderStorage { encoder.storage }
    
    // Position in the Data where we stored the count placeholder.
    private let countPosition: Int
    
    private(set) var count: Int = 0
    
    var codingPath: [CodingKey] {
        get { storage.codingPath }
        set { storage.setCodingPath(newValue) }
    }
    
    init(encoder: _BinaryEncoder) {
        self.encoder = encoder
        self.count = 0
        
        self.countPosition = encoder.storage.data.count
        encoder.storage.write(UInt32(0)) // placeholder
    }
    
    // MARK: - Internal helper
    
    private mutating func bumpCount() {
        count += 1
        storage.replaceCount(at: countPosition, with: UInt32(count))
    }
    
    private mutating func writeNilElement() {
        storage.writePresence(false)
        bumpCount()
    }
    
    // MARK: - Required methods
    
    mutating func encodeNil() throws {
        storage.writePresence(false)
        bumpCount()
    }
    
    mutating func encode(_ value: Bool) throws {
        storage.writePresence(true)
        storage.write(value)
        bumpCount()
    }
    
    mutating func encode(_ value: String) throws {
        storage.writePresence(true)
        storage.write(value)
        bumpCount()
    }
    
    mutating func encode(_ value: Double) throws {
        storage.writePresence(true)
        storage.write(value)
        bumpCount()
    }
    
    mutating func encode(_ value: Int) throws {
        storage.writePresence(true)
        storage.write(Int64(value))
        bumpCount()
    }
    
    mutating func encode(_ value: Int64) throws {
        storage.writePresence(true)
        storage.write(value)
        bumpCount()
    }
    
    mutating func encode(_ value: Data) throws {
        storage.writePresence(true)
        storage.write(value)
        bumpCount()
    }
    
    mutating func encode(_ value: UUID) throws {
        storage.writePresence(true)
        storage.write(value)
        bumpCount()
    }
    
    mutating func encode<T>(_ value: T) throws where T: Encodable {
        // Special-case Optional<Wrapped> so arrays of optionals get a real nil flag.
        if let optional = value as? _OptionalEncodingShim {
            if optional._isNil {
                storage.writePresence(false)   // element is nil
                bumpCount()
            } else {
                storage.writePresence(true)    // element present
                try optional._encodeWrapped(to: encoder)
                bumpCount()
            }
            return
        }
        
        // Special-case leaf / primitive types
        if let data = value as? Data {
            try encode(data)
            return
        }
        if let uuid = value as? UUID {
            try encode(uuid)
            return
        }
        if let string = value as? String {
            try encode(string)
            return
        }
        if let bool = value as? Bool {
            try encode(bool)
            return
        }
        if let int = value as? Int {
            try encode(int)
            return
        }
        if let int64 = value as? Int64 {
            try encode(int64)
            return
        }
        if let double = value as? Double {
            try encode(double)
            return
        }
        
        // Fallback for structured types
        storage.writePresence(true)
        try value.encode(to: encoder)
        bumpCount()
    }
    
    
    // MARK: - Nested containers
    
    mutating func nestedContainer<NestedKey>(
        keyedBy type: NestedKey.Type
    ) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
        storage.writePresence(true)
        bumpCount()
        let nested = BinaryKeyedEncodingContainer<NestedKey>(encoder: encoder)
        return KeyedEncodingContainer(nested)
    }
    
    mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        storage.writePresence(true)
        bumpCount()
        return BinaryUnkeyedEncodingContainer(encoder: encoder)
    }
    
    mutating func superEncoder() -> Encoder {
        encoder
    }
}


// MARK: - Single value container
fileprivate struct BinarySingleValueEncodingContainer: SingleValueEncodingContainer, Sendable {
    
    let encoder: _BinaryEncoder
    private var storage: EncoderStorage { encoder.storage }
    
    var codingPath: [CodingKey] {
        get { storage.codingPath }
        set { storage.setCodingPath(newValue) }
    }
    
    init(encoder: _BinaryEncoder) {
        self.encoder = encoder
    }
    
    mutating func encodeNil() throws {}
    
    mutating func encode(_ value: Bool) throws {
        // Single value containers don't use presence flags
        storage.write(value)
    }
    
    mutating func encode(_ value: String) throws {
        // Single value containers don't use presence flags
        storage.write(value)
    }
    
    mutating func encode(_ value: Double) throws {
        // Single value containers don't use presence flags
        storage.write(value)
    }
    
    mutating func encode(_ value: Int) throws {
        // Single value containers don't use presence flags
        storage.write(Int64(value))
    }
    
    mutating func encode(_ value: Int64) throws {
        storage.write(value)
    }
    
    mutating func encode(_ value: Data) throws {
        // Single value containers don't use presence flags
        storage.write(value)
    }
    
    mutating func encode(_ value: UUID) throws {
        // Single value containers don't use presence flags
        storage.write(value)
    }
    
    mutating func encode<T>(_ value: T) throws where T : Encodable {
        
        if let data = value as? Data {
            try encode(data)
            return
        }
        if let uuid = value as? UUID {
            try encode(uuid)
            return
        }
        if let string = value as? String {
            try encode(string)
            return
        }
        if let bool = value as? Bool {
            try encode(bool)
            return
        }
        if let int = value as? Int {
            try encode(int)
            return
        }
        if let int64 = value as? Int64 {
            try encode(int64)
            return
        }
        if let double = value as? Double {
            try encode(double)
            return
        }
        
        // For other types, let them choose their own container (usually keyed/unkeyed)
        try value.encode(to: encoder)
    }
}


