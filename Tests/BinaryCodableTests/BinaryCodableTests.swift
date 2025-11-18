import Foundation
import Testing
@testable import BinaryCodable

@Suite("BinaryCodable Tests")
struct BinaryCodableTests {
    @Test("Binary Encoder/Decoder String Test")
    func testBinaryStringEncodingDecoding() async throws {
        let someMessage = "Some Message"
        let encoded = try BinaryEncoder().encode(someMessage)
        let decoded = try BinaryDecoder().decode(String.self, from: encoded)
        #expect(decoded == someMessage)
        
    }
    
    @Test("Binary Encoder/Decoder Data Test")
    func testBinaryDataEncodingDecoding() async throws {
        let someData = "Some Message".data(using: .utf8)!
        let encoded = try BinaryEncoder().encode(someData)
        print(encoded)
        let decoded = try BinaryDecoder().decode(Data.self, from: encoded)
        #expect(decoded == someData)
    }
    
    @Test("Binary Encoder/Decoder Bool Test")
    func testBinaryBoolEncodingDecoding() async throws {
        let encoded = try BinaryEncoder().encode(true)
        let decoded = try BinaryDecoder().decode(Bool.self, from: encoded)
        #expect(decoded == true)
    }
    
    @Test("Binary Encoder/Decoder UUID Test")
    func testBinaryUUIDEncodingDecoding() async throws {
        let someData = UUID()
        let encoded = try BinaryEncoder().encode(someData)
        let decoded = try BinaryDecoder().decode(UUID.self, from: encoded)
        #expect(decoded == someData)
    }
    
    @Test("Binary Encoder/Decoder Int64 Test")
    func testBinaryInt64EncodingDecoding() async throws {
        let someData = Int64(100)
        let encoded = try BinaryEncoder().encode(someData)
        let decoded = try BinaryDecoder().decode(Int64.self, from: encoded)
        #expect(decoded == someData)
    }
    
    @Test("Binary Encoder/Decoder Int Test")
    func testBinaryIntEncodingDecoding() async throws {
        let someData = Int(100)
        let encoded = try BinaryEncoder().encode(someData)
        let decoded = try BinaryDecoder().decode(Int.self, from: encoded)
        #expect(decoded == someData)
    }
    
    @Test("Binary Encoder/Decoder Double Test")
    func testBinaryDoubleEncodingDecoding() async throws {
        let someData = Double(100)
        let encoded = try BinaryEncoder().encode(someData)
        let decoded = try BinaryDecoder().decode(Double.self, from: encoded)
        #expect(decoded == someData)
    }
    
    @Test("Binary Encoder/Decoder Optional Test")
    func testBinaryOptionalEncodingDecoding() async throws {
        let someData: String? = "Optional String"
        let encoded = try BinaryEncoder().encode(someData)
        let decoded = try BinaryDecoder().decode(String?.self, from: encoded)
        #expect(decoded == someData)
    }
    
    struct SimpleObject: Codable, Equatable {
        let id: UUID
        let message: String
        let data: Data
    }
    
    @Test("Binary Encoder/Decoder Simple Object Test")
    func testBinarySimpleObjectEncodingDecoding() async throws {
        let someData = SimpleObject(id: UUID(), message: "Hello", data: "World!".data(using: .utf8)!)
        
        let encoded = try BinaryEncoder().encode(someData)
        let decoded = try BinaryDecoder().decode(SimpleObject.self, from: encoded)
        #expect(decoded == someData)
    }
    
    struct NestedObject: Codable, Equatable {
        let id: UUID
        let simple: SimpleObject
        let data: Data
    }
    
    @Test("Binary Encoder/Decoder Nested Object Test")
    func testBinaryNestedObjectEncodingDecoding() async throws {
        let someData = NestedObject(
            id: UUID(),
            simple: .init(
                id: UUID(),
                message: "Hello", data: "World!".data(using: .utf8)!),
            data: "Data".data(using: .utf8)!)
        
        let encoded = try BinaryEncoder().encode(someData)
        let decoded = try BinaryDecoder().decode(NestedObject.self, from: encoded)
        #expect(decoded == someData)
    }
    
    @Test("Binary Encoder/Decoder Array Test")
    func testBinaryArrayEncodingDecoding() async throws {
        
        let someMessages = ["Some Message", "More Message", "Yet Another Message"]
        let encoded = try BinaryEncoder().encode(someMessages)
        let decoded = try BinaryDecoder().decode([String].self, from: encoded)
        #expect(decoded == someMessages)
        
    }
    
    @Test("Binary Encoder/Decoder Empty Array Test")
    func testBinaryEmptyArrayEncodingDecoding() async throws {
        let emptyStrings: [String] = []
        let encoded = try BinaryEncoder().encode(emptyStrings)
        let decoded = try BinaryDecoder().decode([String].self, from: encoded)
        #expect(decoded == emptyStrings)
        
        let emptyInts: [Int] = []
        let encodedInts = try BinaryEncoder().encode(emptyInts)
        let decodedInts = try BinaryDecoder().decode([Int].self, from: encodedInts)
        #expect(decodedInts == emptyInts)
    }
    
    @Test("Binary Encoder/Decoder Array of Int Test")
    func testBinaryIntArrayEncodingDecoding() async throws {
        let someInts = [1, 2, 3, 100, -50, 0, Int.max, Int.min]
        let encoded = try BinaryEncoder().encode(someInts)
        let decoded = try BinaryDecoder().decode([Int].self, from: encoded)
        #expect(decoded == someInts)
    }
    
    @Test("Binary Encoder/Decoder Array of Int64 Test")
    func testBinaryInt64ArrayEncodingDecoding() async throws {
        let someInt64s: [Int64] = [1, 2, 3, 100, -50, 0, Int64.max, Int64.min]
        let encoded = try BinaryEncoder().encode(someInt64s)
        let decoded = try BinaryDecoder().decode([Int64].self, from: encoded)
        #expect(decoded == someInt64s)
    }
    
    @Test("Binary Encoder/Decoder Array of Bool Test")
    func testBinaryBoolArrayEncodingDecoding() async throws {
        let someBools = [true, false, true, false, true]
        let encoded = try BinaryEncoder().encode(someBools)
        let decoded = try BinaryDecoder().decode([Bool].self, from: encoded)
        #expect(decoded == someBools)
    }
    
    @Test("Binary Encoder/Decoder Array of Data Test")
    func testBinaryDataArrayEncodingDecoding() async throws {
        let someData = [
            Data("Hello".utf8),
            Data("World".utf8),
            Data(),
            Data([0x00, 0x01, 0x02, 0xFF])
        ]
        let encoded = try BinaryEncoder().encode(someData)
        let decoded = try BinaryDecoder().decode([Data].self, from: encoded)
        #expect(decoded == someData)
    }
    
    @Test("Binary Encoder/Decoder Array of UUID Test")
    func testBinaryUUIDArrayEncodingDecoding() async throws {
        let someUUIDs = [UUID(), UUID(), UUID()]
        let encoded = try BinaryEncoder().encode(someUUIDs)
        let decoded = try BinaryDecoder().decode([UUID].self, from: encoded)
        #expect(decoded == someUUIDs)
    }
    
    @Test("Binary Encoder/Decoder Array of Double Test")
    func testBinaryDoubleArrayEncodingDecoding() async throws {
        let someDoubles: [Double] = [1.0, 2.5, -3.14, 0.0, Double.pi, Double.greatestFiniteMagnitude]
        let encoded = try BinaryEncoder().encode(someDoubles)
        let decoded = try BinaryDecoder().decode([Double].self, from: encoded)
        #expect(decoded == someDoubles)
    }
    
    @Test("Binary Encoder/Decoder Array of Objects Test")
    func testBinaryObjectArrayEncodingDecoding() async throws {
        let someObjects = [
            SimpleObject(id: UUID(), message: "First", data: Data("1".utf8)),
            SimpleObject(id: UUID(), message: "Second", data: Data("2".utf8)),
            SimpleObject(id: UUID(), message: "Third", data: Data("3".utf8))
        ]
        let encoded = try BinaryEncoder().encode(someObjects)
        let decoded = try BinaryDecoder().decode([SimpleObject].self, from: encoded)
        #expect(decoded == someObjects)
    }
    
    @Test("Binary Encoder/Decoder Optional Int Test")
    func testBinaryOptionalIntEncodingDecoding() async throws {
        let someInt: Int? = 42
        let encoded = try BinaryEncoder().encode(someInt)
        let decoded = try BinaryDecoder().decode(Int?.self, from: encoded)
        #expect(decoded == someInt)
        
        let nilInt: Int? = nil
        let encodedNil = try BinaryEncoder().encode(nilInt)
        let decodedNil = try BinaryDecoder().decode(Int?.self, from: encodedNil)
        #expect(decodedNil == nilInt)
    }
    
    @Test("Binary Encoder/Decoder Optional Int64 Test")
    func testBinaryOptionalInt64EncodingDecoding() async throws {
        let someInt64: Int64? = 42
        let encoded = try BinaryEncoder().encode(someInt64)
        let decoded = try BinaryDecoder().decode(Int64?.self, from: encoded)
        #expect(decoded == someInt64)
        
        let nilInt64: Int64? = nil
        let encodedNil = try BinaryEncoder().encode(nilInt64)
        let decodedNil = try BinaryDecoder().decode(Int64?.self, from: encodedNil)
        #expect(decodedNil == nilInt64)
    }
    
    @Test("Binary Encoder/Decoder Optional Bool Test")
    func testBinaryOptionalBoolEncodingDecoding() async throws {
        let someBool: Bool? = true
        let encoded = try BinaryEncoder().encode(someBool)
        let decoded = try BinaryDecoder().decode(Bool?.self, from: encoded)
        #expect(decoded == someBool)
        
        let nilBool: Bool? = nil
        let encodedNil = try BinaryEncoder().encode(nilBool)
        let decodedNil = try BinaryDecoder().decode(Bool?.self, from: encodedNil)
        #expect(decodedNil == nilBool)
    }
    
    @Test("Binary Encoder/Decoder Optional Data Test")
    func testBinaryOptionalDataEncodingDecoding() async throws {
        let someData: Data? = Data("Hello".utf8)
        let encoded = try BinaryEncoder().encode(someData)
        let decoded = try BinaryDecoder().decode(Data?.self, from: encoded)
        #expect(decoded == someData)
        
        let nilData: Data? = nil
        let encodedNil = try BinaryEncoder().encode(nilData)
        let decodedNil = try BinaryDecoder().decode(Data?.self, from: encodedNil)
        #expect(decodedNil == nilData)
    }
    
    @Test("Binary Encoder/Decoder Optional UUID Test")
    func testBinaryOptionalUUIDEncodingDecoding() async throws {
        let someUUID: UUID? = UUID()
        let encoded = try BinaryEncoder().encode(someUUID)
        let decoded = try BinaryDecoder().decode(UUID?.self, from: encoded)
        #expect(decoded == someUUID)
        
        let nilUUID: UUID? = nil
        let encodedNil = try BinaryEncoder().encode(nilUUID)
        let decodedNil = try BinaryDecoder().decode(UUID?.self, from: encodedNil)
        #expect(decodedNil == nilUUID)
    }
    
    @Test("Binary Encoder/Decoder Optional Double Test")
    func testBinaryOptionalDoubleEncodingDecoding() async throws {
        let someDouble: Double? = 3.14
        let encoded = try BinaryEncoder().encode(someDouble)
        let decoded = try BinaryDecoder().decode(Double?.self, from: encoded)
        #expect(decoded == someDouble)
        
        let nilDouble: Double? = nil
        let encodedNil = try BinaryEncoder().encode(nilDouble)
        let decodedNil = try BinaryDecoder().decode(Double?.self, from: encodedNil)
        #expect(decodedNil == nilDouble)
    }
    
    @Test("Binary Encoder/Decoder Empty String Test")
    func testBinaryEmptyStringEncodingDecoding() async throws {
        let emptyString = ""
        let encoded = try BinaryEncoder().encode(emptyString)
        let decoded = try BinaryDecoder().decode(String.self, from: encoded)
        #expect(decoded == emptyString)
    }
    
    @Test("Binary Encoder/Decoder Empty Data Test")
    func testBinaryEmptyDataEncodingDecoding() async throws {
        let emptyData = Data()
        let encoded = try BinaryEncoder().encode(emptyData)
        let decoded = try BinaryDecoder().decode(Data.self, from: encoded)
        #expect(decoded == emptyData)
    }
    
    @Test("Binary Encoder/Decoder Negative Int Test")
    func testBinaryNegativeIntEncodingDecoding() async throws {
        let negativeInt = -42
        let encoded = try BinaryEncoder().encode(negativeInt)
        let decoded = try BinaryDecoder().decode(Int.self, from: encoded)
        #expect(decoded == negativeInt)
    }
    
    @Test("Binary Encoder/Decoder Negative Int64 Test")
    func testBinaryNegativeInt64EncodingDecoding() async throws {
        let negativeInt64: Int64 = -42
        let encoded = try BinaryEncoder().encode(negativeInt64)
        let decoded = try BinaryDecoder().decode(Int64.self, from: encoded)
        #expect(decoded == negativeInt64)
    }
    
    @Test("Binary Encoder/Decoder Zero Values Test")
    func testBinaryZeroValuesEncodingDecoding() async throws {
        let zeroInt = 0
        let encodedInt = try BinaryEncoder().encode(zeroInt)
        let decodedInt = try BinaryDecoder().decode(Int.self, from: encodedInt)
        #expect(decodedInt == zeroInt)
        
        let zeroInt64: Int64 = 0
        let encodedInt64 = try BinaryEncoder().encode(zeroInt64)
        let decodedInt64 = try BinaryDecoder().decode(Int64.self, from: encodedInt64)
        #expect(decodedInt64 == zeroInt64)
        
        let zeroDouble: Double = 0.0
        let encodedDouble = try BinaryEncoder().encode(zeroDouble)
        let decodedDouble = try BinaryDecoder().decode(Double.self, from: encodedDouble)
        #expect(decodedDouble == zeroDouble)
    }
    
    @Test("Binary Encoder/Decoder Special Double Values Test")
    func testBinarySpecialDoubleValuesEncodingDecoding() async throws {
        let pi = Double.pi
        let encoded = try BinaryEncoder().encode(pi)
        let decoded = try BinaryDecoder().decode(Double.self, from: encoded)
        #expect(decoded == pi)
        
        let negativePi = -Double.pi
        let encodedNeg = try BinaryEncoder().encode(negativePi)
        let decodedNeg = try BinaryDecoder().decode(Double.self, from: encodedNeg)
        #expect(decodedNeg == negativePi)
    }
    
    struct ObjectWithArrays: Codable, Equatable {
        let id: UUID
        let strings: [String]
        let ints: [Int]
        let optionalStrings: [String]?
    }
    
    @Test("Binary Encoder/Decoder Object With Arrays Test")
    func testBinaryObjectWithArraysEncodingDecoding() async throws {
        let object = ObjectWithArrays(
            id: UUID(),
            strings: ["a", "b", "c"],
            ints: [1, 2, 3],
            optionalStrings: ["x", "y"]
        )
        let encoded = try BinaryEncoder().encode(object)
        let decoded = try BinaryDecoder().decode(ObjectWithArrays.self, from: encoded)
        #expect(decoded == object)
        
        let objectWithNil = ObjectWithArrays(
            id: UUID(),
            strings: [],
            ints: [],
            optionalStrings: nil
        )
        let encodedNil = try BinaryEncoder().encode(objectWithNil)
        let decodedNil = try BinaryDecoder().decode(ObjectWithArrays.self, from: encodedNil)
        #expect(decodedNil == objectWithNil)
    }
    
    struct ObjectWithOptionalFields: Codable, Equatable {
        let id: UUID
        let name: String?
        let age: Int?
        let data: Data?
        let uuid: UUID?
        let value: Double?
    }
    
    @Test("Binary Encoder/Decoder Object With Optional Fields Test")
    func testBinaryObjectWithOptionalFieldsEncodingDecoding() async throws {
        let object = ObjectWithOptionalFields(
            id: UUID(),
            name: "Test",
            age: 42,
            data: Data("Hello".utf8),
            uuid: UUID(),
            value: 3.14
        )
        let encoded = try BinaryEncoder().encode(object)
        let decoded = try BinaryDecoder().decode(ObjectWithOptionalFields.self, from: encoded)
        #expect(decoded == object)
        
        let objectWithNils = ObjectWithOptionalFields(
            id: UUID(),
            name: nil,
            age: nil,
            data: nil,
            uuid: nil,
            value: nil
        )
        let encodedNils = try BinaryEncoder().encode(objectWithNils)
        let decodedNils = try BinaryDecoder().decode(ObjectWithOptionalFields.self, from: encodedNils)
        #expect(decodedNils == objectWithNils)
    }
    
    struct ObjectWithNestedArrays: Codable, Equatable {
        let id: UUID
        let nestedStrings: [[String]]
        let nestedInts: [[Int]]
    }
    
    @Test("Binary Encoder/Decoder Nested Arrays Test")
    func testBinaryNestedArraysEncodingDecoding() async throws {
        let object = ObjectWithNestedArrays(
            id: UUID(),
            nestedStrings: [["a", "b"], ["c", "d"], []],
            nestedInts: [[1, 2], [3, 4], []]
        )
        let encoded = try BinaryEncoder().encode(object)
        let decoded = try BinaryDecoder().decode(ObjectWithNestedArrays.self, from: encoded)
        #expect(decoded == object)
    }
    
    struct ComplexNestedObject: Codable, Equatable {
        let id: UUID
        let simple: SimpleObject
        let nested: NestedObject?
        let arrayOfObjects: [SimpleObject]
        let optionalArray: [String]?
    }
    
    @Test("Binary Encoder/Decoder Complex Nested Object Test")
    func testBinaryComplexNestedObjectEncodingDecoding() async throws {
        let object = ComplexNestedObject(
            id: UUID(),
            simple: SimpleObject(id: UUID(), message: "Simple", data: Data("data".utf8)),
            nested: NestedObject(
                id: UUID(),
                simple: SimpleObject(id: UUID(), message: "Nested", data: Data("nested".utf8)),
                data: Data("nestedData".utf8)
            ),
            arrayOfObjects: [
                SimpleObject(id: UUID(), message: "Array1", data: Data("1".utf8)),
                SimpleObject(id: UUID(), message: "Array2", data: Data("2".utf8))
            ],
            optionalArray: ["opt1", "opt2"]
        )
        let encoded = try BinaryEncoder().encode(object)
        let decoded = try BinaryDecoder().decode(ComplexNestedObject.self, from: encoded)
        #expect(decoded == object)
        
        let objectWithNils = ComplexNestedObject(
            id: UUID(),
            simple: SimpleObject(id: UUID(), message: "Simple", data: Data("data".utf8)),
            nested: nil,
            arrayOfObjects: [],
            optionalArray: nil
        )
        let encodedNils = try BinaryEncoder().encode(objectWithNils)
        let decodedNils = try BinaryDecoder().decode(ComplexNestedObject.self, from: encodedNils)
        #expect(decodedNils == objectWithNils)
    }
    
    @Test("Binary Encoder/Decoder Large Array Test")
    func testBinaryLargeArrayEncodingDecoding() async throws {
        let largeArray = Array(0..<1000).map { "Item \($0)" }
        let encoded = try BinaryEncoder().encode(largeArray)
        let decoded = try BinaryDecoder().decode([String].self, from: encoded)
        #expect(decoded == largeArray)
    }
    
    @Test("Binary Encoder/Decoder Unicode String Test")
    func testBinaryUnicodeStringEncodingDecoding() async throws {
        let unicodeStrings = [
            "Hello, 世界",
            "مرحبا",
            "🌍🌎🌏",
            "Привет",
            "नमस्ते"
        ]
        for unicodeString in unicodeStrings {
            let encoded = try BinaryEncoder().encode(unicodeString)
            let decoded = try BinaryDecoder().decode(String.self, from: encoded)
            #expect(decoded == unicodeString)
        }
    }
    
    @Test("Binary Encoder/Decoder Array of Optional Values Test")
    func testBinaryArrayOfOptionalValuesEncodingDecoding() async throws {
        let optionalInts: [Int?] = [1, nil, 3, nil, 5]
        let encoded = try BinaryEncoder().encode(optionalInts)
        let decoded = try BinaryDecoder().decode([Int?].self, from: encoded)
        #expect(decoded == optionalInts)
        
        let optionalStrings: [String?] = ["a", nil, "c", nil, "e"]
        let encodedStrings = try BinaryEncoder().encode(optionalStrings)
        let decodedStrings = try BinaryDecoder().decode([String?].self, from: encodedStrings)
        #expect(decodedStrings == optionalStrings)
    }
    
    enum TestEnum: Codable, Equatable {
        case one,two, three
    }
    
    @Test("Binary Encoder/Decoder Enum Test")
    func testEnumEncodingDecoding() async throws {
        let encoded = try BinaryEncoder().encode(TestEnum.one)
        let decoded = try BinaryDecoder().decode(TestEnum.self, from: encoded)
        #expect(decoded == TestEnum.one)
    }
    
    enum TestValueEnum: Codable, Equatable {
        case one(String),two(Data), three(Int)
    }
    
    @Test("Binary Encoder/Decoder Enum With Associated String Value Test")
    func testEnumStringValueEncodingDecoding() async throws {
        let encoded = try BinaryEncoder().encode(TestValueEnum.one("STRING"))
        let decoded = try BinaryDecoder().decode(TestValueEnum.self, from: encoded)
        #expect(decoded == TestValueEnum.one("STRING"))
    }
    
    @Test("Binary Encoder/Decoder Enum With Associated Data Value Test")
    func testEnumDataValueEncodingDecoding() async throws {
        let encoded = try BinaryEncoder().encode(TestValueEnum.two("STRING".data(using: .utf8)!))
        let decoded = try BinaryDecoder().decode(TestValueEnum.self, from: encoded)
        #expect(decoded == TestValueEnum.two("STRING".data(using: .utf8)!))
    }
    
    @Test("Binary Encoder/Decoder Enum With Associated Int Value Test")
    func testEnumIntValueEncodingDecoding() async throws {
        let encoded = try BinaryEncoder().encode(TestValueEnum.three(100))
        let decoded = try BinaryDecoder().decode(TestValueEnum.self, from: encoded)
        #expect(decoded == TestValueEnum.three(100))
    }
    
    @Test("Binary Encoder/Decoder Date Test")
    func testDateValueEncodingDecoding() async throws {
        let date = Date()
        let encoded = try BinaryEncoder().encode(date)
        let decoded = try BinaryDecoder().decode(Date.self, from: encoded)
        #expect(decoded == date)
    }
    
    @Test("Binary Encoder/Decoder Set Test")
    func testSetValueEncodingDecoding() async throws {
        let set = Set([1,2,3])
        let encoded = try BinaryEncoder().encode(set)
        let decoded = try BinaryDecoder().decode(Set<Int>.self, from: encoded)
        #expect(decoded == set)
    }
    
    @Test("Binary Encoder/Decoder Dictionary Test")
    func testDictIntValueEncodingDecoding() async throws {
        let dict = ["One": "1", "Two": "2", "3": "3.0"] as [String : String]
        let encoded = try BinaryEncoder().encode(dict)
        let decoded = try BinaryDecoder().decode([String : String].self, from: encoded)
        #expect(decoded == dict)
    }
    
    @Test("Binary Encoder/Decoder Data Dictionary Test")
    func testDictDataValueEncodingDecoding() async throws {
        let dict = ["One": "1".data(using: .utf8)!, "Two": "2".data(using: .utf8)!, "3": "3.0".data(using: .utf8)!] as [String : Data]
        let encoded = try BinaryEncoder().encode(dict)
        let decoded = try BinaryDecoder().decode([String : Data].self, from: encoded)
        #expect(decoded == dict)
    }
    
    @Test("Binary Encoder/Decoder Nested Dictionary Test")
    func testNestedDictIntValueEncodingDecoding() async throws {
        let dict = ["One": ["One": "1", "Two": "2", "Three": "3.0"], "Two":["One": "1", "Two": "2", "Three": "3.0"], "Three": ["One": "1", "Two": "2", "Three": "3.0"], "Four": ["One": "1", "Two": "2", "Three": "3.0"]] as [String : [String: String]]
        let encoded = try BinaryEncoder().encode(dict)
        let decoded = try BinaryDecoder().decode([String : [String: String]].self, from: encoded)
        #expect(decoded == dict)
    }
}
