import Foundation

extension String: DagCBORCodable {
    @inlinable public init(dagCBOR reader: inout DagCBORReader) throws { self = try reader.readText() }
    @inlinable public func writeDagCBOR(to writer: inout DagCBORWriter) throws { writer.writeText(self) }
}

extension Bool: DagCBORCodable {
    @inlinable public init(dagCBOR reader: inout DagCBORReader) throws { self = try reader.readBool() }
    @inlinable public func writeDagCBOR(to writer: inout DagCBORWriter) throws { writer.writeBool(self) }
}

extension UInt64: DagCBORCodable {
    @inlinable public init(dagCBOR reader: inout DagCBORReader) throws { self = try reader.readUInt64() }
    @inlinable public func writeDagCBOR(to writer: inout DagCBORWriter) throws { writer.writeUInt64(self) }
}

extension UInt32: DagCBORCodable {
    @inlinable public init(dagCBOR reader: inout DagCBORReader) throws {
        self = UInt32(try reader.readUInt64(max: UInt64(UInt32.max)))
    }
    @inlinable public func writeDagCBOR(to writer: inout DagCBORWriter) throws { writer.writeUInt64(UInt64(self)) }
}

extension UInt16: DagCBORCodable {
    @inlinable public init(dagCBOR reader: inout DagCBORReader) throws {
        self = UInt16(try reader.readUInt64(max: UInt64(UInt16.max)))
    }
    @inlinable public func writeDagCBOR(to writer: inout DagCBORWriter) throws { writer.writeUInt64(UInt64(self)) }
}

extension Int64: DagCBORCodable {
    @inlinable public init(dagCBOR reader: inout DagCBORReader) throws { self = try reader.readInt64() }
    @inlinable public func writeDagCBOR(to writer: inout DagCBORWriter) throws { writer.writeInt64(self) }
}

extension Int: DagCBORCodable {
    @inlinable public init(dagCBOR reader: inout DagCBORReader) throws {
        guard let value = Int(exactly: try reader.readInt64()) else { throw DagCBORError.integerOverflow }
        self = value
    }
    @inlinable public func writeDagCBOR(to writer: inout DagCBORWriter) throws { writer.writeInt64(Int64(self)) }
}

extension Array: DagCBORCodable where Element: DagCBORCodable {
    @inlinable public init(dagCBOR reader: inout DagCBORReader) throws {
        let count = try reader.readArrayCount()
        var elements: [Element] = []
        elements.reserveCapacity(count)
        for _ in 0..<count {
            elements.append(try Element(dagCBOR: &reader))
        }
        self = elements
    }

    @inlinable public func writeDagCBOR(to writer: inout DagCBORWriter) throws {
        try writer.writeArrayHeader(count: count)
        for element in self {
            try element.writeDagCBOR(to: &writer)
        }
    }
}

/// A `String`-backed enum is its raw value, as `Codable` encodes it:
/// conforming takes only `extension E: DagCBORCodable {}`.
extension DagCBORCodable where Self: RawRepresentable, RawValue == String {
    @inlinable public init(dagCBOR reader: inout DagCBORReader) throws {
        guard let value = Self(rawValue: try reader.readText()) else { throw DagCBORError.invalidCBOR }
        self = value
    }

    @inlinable public func writeDagCBOR(to writer: inout DagCBORWriter) throws {
        writer.writeText(rawValue)
    }
}
