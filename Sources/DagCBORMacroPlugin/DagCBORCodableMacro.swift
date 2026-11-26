import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros

@main
struct DagCBORMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [DagCBORCodableMacro.self]
}

public struct DagCBORCodableMacro: ExtensionMacro {
    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    /// A coded stored property: its map key, and its type without `Optional`.
    struct Field {
        let name: String
        let key: String
        let type: String
        let isOptional: Bool
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw Failure("@DagCBORCodable applies to a struct")
        }
        let fields = try codedFields(of: structDecl).sorted { keyPrecedes($0.key, $1.key) }
        let access = accessModifier(of: structDecl)
        let required = fields.filter { !$0.isOptional }.count

        var read = ["_ = try reader.readMapCount()"]
        for (index, field) in fields.enumerated() {
            let key = literal(field.key)
            if field.isOptional {
                read.append("var field\(index): \(field.type)? = nil")
                read.append("if reader.consumeKey(\(key)) {")
                read.append("    let value: \(field.type) = try .init(dagCBOR: &reader)")
                read.append("    field\(index) = value")
                read.append("}")
            } else {
                read.append("try reader.readKey(\(key))")
                read.append("let field\(index): \(field.type) = try .init(dagCBOR: &reader)")
            }
        }
        read += fields.enumerated().map { "self.\($1.name) = field\($0)" }
        read.append("try self.checkDagCBORFields()")

        let optionals = fields.filter(\.isOptional).map { " + (self.\($0.name) == nil ? 0 : 1)" }.joined()
        var write = ["try writer.writeMapHeader(count: \(required)\(optionals))"]
        for field in fields {
            let key = literal(field.key)
            if field.isOptional {
                write.append("if let value = self.\(field.name) {")
                write.append("    writer.writeText(\(key))")
                write.append("    try value.writeDagCBOR(to: &writer)")
                write.append("}")
            } else {
                write.append("writer.writeText(\(key))")
                write.append("try self.\(field.name).writeDagCBOR(to: &writer)")
            }
        }

        let conformance = protocols.isEmpty ? "" : ": DagCBORKit.DagCBORCodable"
        let source = """
        extension \(type.trimmedDescription)\(conformance) {
            \(access)init(dagCBOR reader: inout DagCBORKit.DagCBORReader) throws {
                \(read.joined(separator: "\n        "))
            }

            \(access)func writeDagCBOR(to writer: inout DagCBORKit.DagCBORWriter) throws {
                \(write.joined(separator: "\n        "))
            }
        }
        """
        return [try ExtensionDeclSyntax("\(raw: source)")]
    }

    /// The stored properties coded, with their keys: those `CodingKeys`
    /// lists, else every stored instance property.
    static func codedFields(of decl: StructDeclSyntax) throws -> [Field] {
        var stored: [String: (type: TypeSyntax, settable: Bool)] = [:]
        var order: [String] = []
        for member in decl.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  !variable.modifiers.contains(where: { ["static", "class"].contains($0.name.text) }) else { continue }
            let isLet = variable.bindingSpecifier.tokenKind == .keyword(.let)
            for binding in variable.bindings {
                guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
                    throw Failure("@DagCBORCodable: a stored property must be a plain name")
                }
                if let accessors = binding.accessorBlock, isComputed(accessors) { continue }
                guard let type = binding.typeAnnotation?.type else {
                    throw Failure("@DagCBORCodable: '\(name)' needs a type annotation")
                }
                // A `let` with a value is never read; one with no value is.
                stored[name] = (type, !(isLet && binding.initializer != nil))
                order.append(name)
            }
        }

        var keyed: [(name: String, key: String)] = order.map { ($0, $0) }
        if let codingKeys = decl.memberBlock.members
            .compactMap({ $0.decl.as(EnumDeclSyntax.self) })
            .first(where: { $0.name.text == "CodingKeys" }) {
            keyed = try codingKeys.memberBlock.members
                .compactMap { $0.decl.as(EnumCaseDeclSyntax.self) }
                .flatMap(\.elements)
                .map { element in
                    let name = element.name.text
                    guard let raw = element.rawValue else { return (name, name) }
                    guard let text = raw.value.as(StringLiteralExprSyntax.self)?.representedLiteralValue else {
                        throw Failure("@DagCBORCodable: CodingKeys.\(name) needs a plain string raw value")
                    }
                    return (name, text)
                }
        }

        return try keyed.map { name, key in
            guard let property = stored[name] else {
                throw Failure("@DagCBORCodable: CodingKeys.\(name) names no stored property")
            }
            guard property.settable else {
                throw Failure("@DagCBORCodable: '\(name)' is a 'let' with a value, which reading cannot set")
            }
            let (type, isOptional) = unwrappingOptional(property.type)
            return Field(name: name, key: key, type: type, isOptional: isOptional)
        }
    }

    static func isComputed(_ accessors: AccessorBlockSyntax) -> Bool {
        switch accessors.accessors {
        case .getter:
            return true
        case .accessors(let list):
            return list.contains { !["willSet", "didSet"].contains($0.accessorSpecifier.text) }
        }
    }

    static func unwrappingOptional(_ type: TypeSyntax) -> (String, Bool) {
        if let optional = type.as(OptionalTypeSyntax.self) {
            return (optional.wrappedType.trimmedDescription, true)
        }
        let text = type.trimmedDescription
        if text.hasPrefix("Optional<"), text.hasSuffix(">") {
            return (String(text.dropFirst("Optional<".count).dropLast()), true)
        }
        return (text, false)
    }

    static func accessModifier(of decl: StructDeclSyntax) -> String {
        for modifier in decl.modifiers {
            switch modifier.name.text {
            case "public", "open": return "public "
            case "package": return "package "
            default: continue
            }
        }
        return ""
    }

    /// `text` as a Swift string literal.
    static func literal(_ text: String) -> String {
        StringLiteralExprSyntax(content: text).description
    }

    /// The canonical key order: shorter first, then bytewise.
    static func keyPrecedes(_ a: String, _ b: String) -> Bool {
        let (aBytes, bBytes) = (Array(a.utf8), Array(b.utf8))
        if aBytes.count != bBytes.count { return aBytes.count < bBytes.count }
        return aBytes.lexicographicallyPrecedes(bBytes)
    }
}
