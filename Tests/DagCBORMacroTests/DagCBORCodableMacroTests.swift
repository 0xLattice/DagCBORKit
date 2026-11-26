import SwiftSyntaxMacros
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosTestSupport
import XCTest
import DagCBORMacroPlugin

final class DagCBORCodableMacroTests: XCTestCase {
    let macros = ["DagCBORCodable": MacroSpec(type: DagCBORCodableMacro.self, conformances: ["DagCBORCodable"])]

    func test_fieldsInCanonicalKeyOrder_optionalsAbsentWhenNil() {
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
            }

            extension Header: DagCBORKit.DagCBORCodable {
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

    func test_codingKeysChooseTheFieldsAndTheirKeys() {
        assertMacroExpansion(
            """
            @DagCBORCodable
            struct Entry {
                let identifier: String
                var cached: Int = 0
                enum CodingKeys: String, CodingKey {
                    case identifier = "id"
                }
            }
            """,
            expandedSource: """
            struct Entry {
                let identifier: String
                var cached: Int = 0
                enum CodingKeys: String, CodingKey {
                    case identifier = "id"
                }
            }

            extension Entry: DagCBORKit.DagCBORCodable {
                init(dagCBOR reader: inout DagCBORKit.DagCBORReader) throws {
                    _ = try reader.readMapCount()
                    try reader.readKey("id")
                    let field0: String = try .init(dagCBOR: &reader)
                    self.identifier = field0
                    try self.checkDagCBORFields()
                }

                func writeDagCBOR(to writer: inout DagCBORKit.DagCBORWriter) throws {
                    try writer.writeMapHeader(count: 1)
                    writer.writeText("id")
                    try self.identifier.writeDagCBOR(to: &writer)
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
