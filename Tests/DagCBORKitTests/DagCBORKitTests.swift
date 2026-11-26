import Foundation
import Testing
import DagCBORMacro

@DagCBORCodable
struct Sample: Equatable {
    enum Kind: String, Codable, DagCBORCodable { case plain, special }

    let height: UInt64
    let delta: Int64
    let name: String
    let note: String?
    let kind: Kind
    let flags: [Bool]
    let small: UInt16

    enum CodingKeys: String, CodingKey {
        case height, delta, name, note, kind, flags
        case small = "s"
    }
}

@DagCBORCodable
struct Checked {
    let low: UInt64
    let high: UInt64

    struct Inverted: Error {}

    func checkDagCBORFields() throws {
        guard low <= high else { throw Inverted() }
    }
}

/// Keyword names, a shared type, and a key renamed by `CodingKeys`.
@DagCBORCodable
struct Keyed {
    let `default`, b: UInt64
    let note: String?

    enum CodingKeys: String, CodingKey {
        case `default`, note
        case b = "bee"
    }
}

/// What a reader or writer does is stated in bytes: the canonical DAG-CBOR
/// of a value, and the verdict on every other spelling.
@Suite("DAG-CBOR is read and written in its one canonical form")
struct DagCBORKitTests {
    static let sample = Sample(height: 500, delta: -1, name: "é", note: nil, kind: .special, flags: [true, false], small: 24)

    /// `parts` joined.
    static func bytes(_ parts: [UInt8]...) -> [UInt8] { parts.flatMap { $0 } }

    /// A text item.
    static func text(_ string: String) -> [UInt8] {
        var writer = DagCBORWriter()
        writer.writeText(string)
        return writer.bytes
    }

    /// `Sample` by hand: keys shortest first, then bytewise; `note` absent.
    static let sampleBytes: [UInt8] = bytes(
        [0xa6],
        text("s"), [0x18, 0x18],
        text("kind"), text("special"),
        text("name"), [0x62, 0xc3, 0xa9],
        text("delta"), [0x20],
        text("flags"), [0x82, 0xf5, 0xf4],
        text("height"), [0x19, 0x01, 0xf4]
    )

    @Test("A struct is written field by field in canonical key order")
    func writesCanonicalBytes() throws {
        #expect(try DagCBORCanonical.encode(Self.sample) == Self.sampleBytes)
        #expect(try DagCBORCanonical.decode(Sample.self, from: Data(Self.sampleBytes)) == Self.sample)
    }

    @Test("A present optional is written, between its neighbours in key order")
    func writesPresentOptional() throws {
        var value = Self.sample
        value = Sample(height: value.height, delta: value.delta, name: value.name, note: "n", kind: value.kind, flags: value.flags, small: value.small)
        let bytes = try DagCBORCanonical.encode(value)
        #expect(bytes.first == 0xa7)
        #expect(try DagCBORCanonical.decode(Sample.self, from: Data(bytes)) == value)
        let name = bytes.firstRange(of: Array("name".utf8))!.lowerBound
        let note = bytes.firstRange(of: Array("note".utf8))!.lowerBound
        let delta = bytes.firstRange(of: Array("delta".utf8))!.lowerBound
        #expect(name < note && note < delta)
    }

    @Test("Every other spelling of a value is refused")
    func refusesOtherSpellings() throws {
        let bytes = Self.sampleBytes
        func refused(_ input: [UInt8]) -> Bool {
            (try? DagCBORCanonical.decode(Sample.self, from: Data(input))) == nil
        }
        // Trailing bytes, a wider head, a null optional, an unknown key, keys
        // out of order, a truncation, a too-large small integer, ill-formed
        // UTF-8 (read as U+FFFD, which writes back otherwise).
        let rest = Array(bytes[5...])
        let kindEntry = Array(bytes[5..<18])
        let nameEntry = Array(bytes[18..<26])
        let afterName = Array(bytes[26...])
        let head = Array(bytes[..<5])
        let entries = Array(bytes.dropFirst())
        let spellings: [[UInt8]] = [
            bytes + [0x00],
            Self.bytes([0xa6], Self.text("s"), [0x19, 0x00, 0x18], rest),
            Self.bytes([0xa7], entries, Self.text("note"), [0xf6]),
            Self.bytes([0xa7], entries, Self.text("z"), [0x00]),
            Self.bytes(head, nameEntry, kindEntry, afterName),
            Array(bytes.dropLast()),
            Self.bytes([0xa6], Self.text("s"), [0x1a, 0x00, 0x01, 0x00, 0x00], rest),
            Self.bytes(Array(bytes[..<18]), Self.text("name"), [0x62, 0xc3, 0x28], afterName),
        ]
        for spelling in spellings {
            #expect(refused(spelling), "\(spelling)")
        }
    }

    @Test("Codable and DAG-CBOR key the same fields alike")
    func codableKeysLikeDagCBOR() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = String(decoding: try encoder.encode(Keyed(default: 1, b: 2, note: "n")), as: UTF8.self)
        #expect(json == #"{"bee":2,"default":1,"note":"n"}"#)
        let absent = String(decoding: try encoder.encode(Keyed(default: 1, b: 2, note: nil)), as: UTF8.self)
        #expect(absent == #"{"bee":2,"default":1}"#)
        #expect(try JSONDecoder().decode(Keyed.self, from: Data(json.utf8)).b == 2)
        let bytes = Self.bytes([0xa2], Self.text("bee"), [0x02], Self.text("default"), [0x01])
        #expect(try DagCBORCanonical.encode(Keyed(default: 1, b: 2, note: nil)) == bytes)
    }

    @Test("A rule over the fields together refuses a value whose fields read")
    func checksFieldsTogether() throws {
        #expect(throws: Checked.Inverted.self) {
            try JSONDecoder().decode(Checked.self, from: Data(#"{"low":2,"high":1}"#.utf8))
        }
        #expect(throws: Never.self) { try JSONDecoder().decode(Checked.self, from: Data(#"{"low":1,"high":2}"#.utf8)) }
        let ordered = try DagCBORCanonical.encode(Checked(low: 1, high: 2))
        #expect(try DagCBORCanonical.decode(Checked.self, from: Data(ordered)).high == 2)
        let inverted = try DagCBORCanonical.encode(Checked(low: 2, high: 1))
        #expect(throws: Checked.Inverted.self) { try DagCBORCanonical.decode(Checked.self, from: Data(inverted)) }
    }

    @Test("Integers are written shortest-form and read back within their type")
    func integers() throws {
        let cases: [(Int64, [UInt8])] = [
            (.min, [0x3b, 0x7f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]), (-24, [0x37]), (-25, [0x38, 0x18]),
            (0, [0x00]), (23, [0x17]), (24, [0x18, 0x18]), (.max, [0x1b, 0x7f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]),
        ]
        for (value, bytes) in cases {
            #expect(try DagCBORCanonical.encode(value) == bytes)
            #expect(try DagCBORCanonical.decode(Int64.self, from: Data(bytes)) == value)
        }
        #expect((try? DagCBORCanonical.decode(Int64.self, from: Data([0x1b, 0x80, 0, 0, 0, 0, 0, 0, 0]))) == nil)
        #expect((try? DagCBORCanonical.decode(UInt16.self, from: Data([0x1a, 0x00, 0x01, 0x00, 0x00]))) == nil)
        #expect(try DagCBORCanonical.decode(UInt64.self, from: Data([0x1b] + [UInt8](repeating: 0xff, count: 8))) == .max)
    }

    @Test("A collection over the limit is neither written nor read")
    func collectionLimit() throws {
        let over = [Bool](repeating: false, count: Int(DagCBORCanonical.maxCollectionCount) + 1)
        #expect(throws: DagCBORError.self) { try DagCBORCanonical.encode(over) }
        let head: [UInt8] = [0x9a, 0x00, 0x01, 0x00, 0x01]
        let input = Data(head + [UInt8](repeating: 0xf4, count: over.count))
        #expect(throws: DagCBORError.self) { try DagCBORCanonical.decode([Bool].self, from: input) }
    }
}
