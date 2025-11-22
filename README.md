# BinaryCodable

![Apple](https://img.shields.io/badge/Platform-Apple-999999?logo=apple&logoColor=white)
![Linux](https://img.shields.io/badge/Platform-Linux-FCC624?logo=linux&logoColor=black)
![Android](https://img.shields.io/badge/Platform-Android-3DDC84?logo=android&logoColor=white)

A high-performance, type-safe binary encoding and decoding library for Swift that seamlessly integrates with Swift's `Codable` protocol.

## ✨ Features

- 🔄 **Full Codable Support** - Works with any type conforming to `Encodable`/`Decodable`
- ⚡ **High Performance** - Efficient binary format with little-endian encoding
- 🛡️ **Type Safe** - Leverages Swift's type system for compile-time safety
- 📦 **Comprehensive Type Support** - Built-in support for:
  - Primitives: `Bool`, `Int`, `Int64`, `Double`
  - Collections: `String`, `Data`, `UUID`
  - Arrays: `[T]` for any `Codable` type
  - Optionals: `T?` for any `Codable` type
  - Nested structures and complex objects
- 🎯 **Zero Dependencies** - Pure Swift implementation using Foundation

## 📋 Requirements

- Swift 6.2+
- iOS 13.0+ / macOS 10.15+ / tvOS 13.0+ / watchOS 6.0+
- Xcode 15.0+

## 🖥️ Platform Support

BinaryCodable is designed to work across multiple platforms:

- **Apple Platforms** ✅
  - iOS 13.0+
  - macOS 10.15+
  - tvOS 13.0+
  - watchOS 6.0+
  
- **Linux** ✅
  - Ubuntu 18.04+
  - Other Linux distributions with Swift 6.2+ support
  
- **Android** ✅
  - Android 5.0+ (API level 21+)
  - Via [Swift SDK for Android](https://www.swift.org/documentation/articles/swift-sdk-for-android-getting-started.html)

The library uses only Foundation APIs that are available across all supported platforms, ensuring consistent behavior regardless of the target platform.

## 📦 Installation

### Swift Package Manager

Add `BinaryCodable` to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/NeedleTailsOrganization/binary-codable.git", from: "1.0.0")
]
```

Or add it through Xcode:
1. File → Add Packages...
2. Enter the repository URL
3. Select the version or branch you want to use

## 🚀 Quick Start

### Basic Usage

```swift
import BinaryCodable

// Encode a simple value
let message = "Hello, World!"
let encoder = BinaryEncoder()
let encoded = try encoder.encode(message)

// Decode it back
let decoder = BinaryDecoder()
let decoded = try decoder.decode(String.self, from: encoded)
print(decoded) // "Hello, World!"
```

### Encoding Custom Types

```swift
struct User: Codable {
    let id: UUID
    let name: String
    let age: Int
    let email: String?
}

let user = User(
    id: UUID(),
    name: "John Doe",
    age: 30,
    email: "john@example.com"
)

// Encode
let encoder = BinaryEncoder()
let data = try encoder.encode(user)

// Decode
let decoder = BinaryDecoder()
let decodedUser = try decoder.decode(User.self, from: data)
```

### Working with Arrays

```swift
let numbers = [1, 2, 3, 4, 5]
let encoded = try BinaryEncoder().encode(numbers)
let decoded = try BinaryDecoder().decode([Int].self, from: encoded)
```

### Nested Structures

```swift
struct Address: Codable {
    let street: String
    let city: String
    let zipCode: String
}

struct Person: Codable {
    let name: String
    let address: Address
    let phoneNumbers: [String]
}

let person = Person(
    name: "Jane Smith",
    address: Address(street: "123 Main St", city: "Anytown", zipCode: "12345"),
    phoneNumbers: ["555-0100", "555-0101"]
)

let encoded = try BinaryEncoder().encode(person)
let decoded = try BinaryDecoder().decode(Person.self, from: encoded)
```

## 📐 Binary Format Specification

The binary format uses little-endian encoding for all multi-byte values:

- **Bool**: 1 byte (0 or 1)
- **Int64**: 8 bytes, little-endian
- **UInt64**: 8 bytes, little-endian, native unsigned encoding
- **Double**: 8 bytes, IEEE 754, little-endian
- **Float**: 4 bytes, IEEE 754, little-endian, native 32-bit encoding
- **UUID**: 16 raw bytes
- **String**: UInt32 length (LE) + UTF-8 bytes
- **Data**: UInt32 length (LE) + raw bytes
- **Field**: 1-byte presence flag, then value if present
- **Array**: UInt32 count (LE) + [presence flag + value] for each element

**Version 2 Format**: Header consists of:
1. Version byte (2)
2. Magic header (4 bytes: `0x4E54424E`)
3. Type name (UInt32 length + UTF-8 string)
4. Payload (encoded data)

## 📋 Version Compatibility

BinaryCodable uses version 2 format for all encodings, which provides full support for all types with no limitations. The decoder automatically handles backward compatibility with version 1 format.

### Current Format (Version 2)

- **Full UInt64 Range**: Native 64-bit unsigned encoding supports the complete range 
  (0 to 18,446,744,073,709,551,615)
- **Exact Float Precision**: Native 32-bit IEEE 754 encoding preserves exact precision
- **No Limitations**: All types are encoded with their native representations

### Legacy Format (Version 1)

When decoding version 1 data, the following limitations apply:

- **UInt/UInt64**: Limited to ≤ `Int64.max` (9,223,372,036,854,775,807) due to Int64 wire format
- **Float**: Encoded as Double (64-bit), which may cause slight precision differences
- **Magic Header**: Optional in version 1, required in version 2+

> **Note**: All new encodings use version 2 format with no limitations. Legacy format limitations only affect decoding of data created with version 1 of the library.

## 🔒 Security

BinaryCodable has no explicit size limits and is only constrained by available system memory. This allows the library to handle data of any size, making it suitable for a wide range of applications including:

- Large images or media files
- Extensive document content
- Large datasets or bulk operations
- Scientific computing applications

> **Note**: When processing untrusted data, consider implementing your own size limits or validation based on your application's security requirements and available system resources.

## 🧪 Testing

The library includes comprehensive test coverage for:
- All primitive types
- Arrays and nested arrays
- Optionals and optional arrays
- Complex nested structures
- Edge cases (empty values, negative numbers, Unicode strings)

Run tests using:

```bash
swift test
```

## 📝 License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📧 Contact

For questions or support, please open an issue on the GitHub repository.

---

Made with ❤️ by [NeedleTails Organization](https://github.com/NeedleTailsOrganization)

