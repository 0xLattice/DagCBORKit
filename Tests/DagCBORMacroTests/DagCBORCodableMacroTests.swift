import SwiftSyntaxMacros
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosTestSupport
import XCTest
import DagCBORMacroPlugin

final class DagCBORCodableMacroTests: XCTestCase {
    let macros = ["DagCBORCodable": MacroSpec(type: DagCBORCodableMacro.self, conformances: ["DagCBORCodable", "Encodable", "Decodable"])]

    func test_oneFieldListWritesBothConformances() {
        assertMacroExpansion(
            """
            @DagCBORCodable
            public struct Header {
                public let version: UInt16
                public let parent: Link?
                public var nonce: UInt64
                static let zero = 0
                var doubled: UInt64 { nonce * 2 }
            }
            """,
            expandedSource: """
            public struct Header {
                public let version: UInt16
                public let parent: Link?
                public var nonce: UInt64
                static let zero = 0
                var doubled: UInt64 { nonce * 2 }

                enum CodingKeys: String, CodingKey {
                    case version
                    case parent
                    case nonce
                }
            }

            extension Header: DagCBORKit.DagCBORCodable, Encodable, Decodable {
                public init(from decoder: any Decoder) throws {
                    let container = try decoder.container(keyedBy: DagCBORKit.DagCBORKey.self)
                    try DagCBORKit.DagCBORKey.refuse(Self.refusedKeys, except: ["version", "parent", "nonce"], in: container)
                    self.version = try container.decode(UInt16.self, forKey: DagCBORKit.DagCBORKey("version"))
                    self.parent = try container.decodeIfPresent(Link.self, forKey: DagCBORKit.DagCBORKey("parent"))
                    self.nonce = try container.decode(UInt64.self, forKey: DagCBORKit.DagCBORKey("nonce"))
                    try self.checkDagCBORFields()
                }

                public func encode(to encoder: any Encoder) throws {
                    var container = encoder.container(keyedBy: DagCBORKit.DagCBORKey.self)
                    try container.encode(self.version, forKey: DagCBORKit.DagCBORKey("version"))
                    try container.encodeIfPresent(self.parent, forKey: DagCBORKit.DagCBORKey("parent"))
                    try container.encode(self.nonce, forKey: DagCBORKit.DagCBORKey("nonce"))
                }

                public init(dagCBOR reader: inout DagCBORKit.DagCBORReader) throws {
                    _ = try reader.readMapCount()
                    try reader.readKey("nonce")
                    let field0: UInt64 = try .init(dagCBOR: &reader)
                    var field1: Link? = nil
                    if reader.consumeKey("parent") {
                        let value: Link = try .init(dagCBOR: &reader)
                        field1 = value
                    }
                    try reader.readKey("version")
                    let field2: UInt16 = try .init(dagCBOR: &reader)
                    self.nonce = field0
                    self.parent = field1
                    self.version = field2
                    try self.checkDagCBORFields()
                }

                public func writeDagCBOR(to writer: inout DagCBORKit.DagCBORWriter) throws {
                    try writer.writeMapHeader(count: 2 + (self.parent == nil ? 0 : 1))
                    writer.writeText("nonce")
                    try self.nonce.writeDagCBOR(to: &writer)
                    if let value = self.parent {
                        writer.writeText("parent")
                        try value.writeDagCBOR(to: &writer)
                    }
                    writer.writeText("version")
                    try self.version.writeDagCBOR(to: &writer)
                }
            }
            """,
            macroSpecs: macros
        )
    }

    func test_refusesWhatItCannotRead() {
        let cases = [
            ("enum E {\n    case a\n}", "@DagCBORCodable applies to a struct"),
            ("struct S {\n    let x = 1\n}", "@DagCBORCodable: 'x' needs a type annotation"),
            ("struct S {\n    let x: Int = 1\n}", "@DagCBORCodable: 'x' is a 'let' with a value, which reading cannot set"),
            ("struct S {\n    let x: Int\n    enum CodingKeys: String, CodingKey {\n        case y\n    }\n}", "@DagCBORCodable: CodingKeys.y names no stored property"),
            ("struct S {\n    @Boxed var x: Int\n}", "@DagCBORCodable: 'x' has an attribute (a property wrapper?), which is not supported"),
            ("struct S {\n    var x: Int!\n}", "@DagCBORCodable: 'x' is implicitly unwrapped; declare it optional"),
            ("struct S {\n    #if DEBUG\n    var x: Int = 0\n    #endif\n}", "@DagCBORCodable: members under #if are not supported"),
            ("struct S {\n    let x: Int\n    enum CodingKeys: String, CodingKey {\n        case x\n        #if DEBUG\n        case y\n        #endif\n    }\n}", "@DagCBORCodable: CodingKeys may hold only cases"),
            ("struct S {\n    let x: Int\n    enum CodingKeys: String, CodingKey {\n        case x\n        var stringValue: String {\n            \"z\"\n        }\n    }\n}", "@DagCBORCodable: CodingKeys may hold only cases"),
            ("struct S {\n    let x: Int\n    typealias CodingKeys = OtherKeys\n}", "@DagCBORCodable: CodingKeys must be an enum of cases"),
        ]
        for (source, message) in cases {
            assertMacroExpansion(
                "@DagCBORCodable\n" + source,
                expandedSource: source,
                diagnostics: [DiagnosticSpec(message: message, line: 1, column: 1)],
                macroSpecs: macros
            )
        }
    }
}
