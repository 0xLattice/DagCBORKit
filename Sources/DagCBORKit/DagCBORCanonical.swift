import Foundation

public enum DagCBORError: Error {
    case unsupportedType
    case integerOverflow
    case unexpectedEnd
    case invalidCBOR
    /// The bytes decode, but are not the bytes their value encodes to.
    case nonCanonical
    /// An array or map longer than ``DagCBORCanonical/maxCollectionCount``.
    case collectionTooLarge
}

/// The canonical form: one encoding per value.
public enum DagCBORCanonical {
    /// The most elements an array or map may hold. Writers refuse more, so
    /// nothing is written that a reader refuses.
    public static let maxCollectionCount: UInt64 = 65_536

    /// Whether map key `a` sorts before `b` in the canonical order: shorter
    /// first, then bytewise.
    @inlinable public static func keyPrecedes(_ a: String, _ b: String) -> Bool {
        let aLength = a.utf8.count
        let bLength = b.utf8.count
        if aLength != bLength { return aLength < bLength }
        return a.utf8.lexicographicallyPrecedes(b.utf8)
    }

    @inlinable public static func encode<T: DagCBORCodable>(_ value: T) throws -> [UInt8] {
        var writer = DagCBORWriter()
        try value.writeDagCBOR(to: &writer)
        return writer.bytes
    }

    /// Decodes `data` only if it is the one encoding of the value it holds:
    /// writing the result must give back exactly these bytes. That single
    /// rule refuses every second spelling of a value (trailing bytes,
    /// non-minimal heads, unsorted or repeated keys, ignored fields, ...),
    /// so one value has one CID.
    @inlinable public static func decode<T: DagCBORCodable>(_: T.Type, from data: Data) throws -> T {
        var reader = DagCBORReader(data)
        let decoded = try T(dagCBOR: &reader)
        guard try encode(decoded) == reader.bytes else { throw DagCBORError.nonCanonical }
        return decoded
    }
}
