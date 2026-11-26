import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros

@main
struct DagCBORMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [DagCBORCodableMacro.self]
}

public struct DagCBORCodableMacro: ExtensionMacro, MemberMacro {
    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    /// A coded stored property: its map key, and its type without `Optional`.
    struct Field {
        /// The property as code refers to it, with backticks if it had them.
        let name: String
        let key: String
        let type: String
        let isOptional: Bool
    }

    /// `CodingKeys` listing the coded fields, when the struct declares none:
    /// synthesized `Codable` then keys exactly the fields the macro writes,
    /// and a `CodingKeys` declared elsewhere fails to compile as a
    /// redeclaration. Errors are reported by the extension.
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self),
              (try? declaredCodingKeys(of: structDecl)) == .some(nil),
              let fields = try? codedFields(of: structDecl) else { return [] }
        let cases = fields.map { "case \($0.name)" }.joined(separator: "\n    ")
        return ["enum CodingKeys: String, CodingKey {\n    \(raw: cases)\n}"]
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
        var stored: [String: (spelling: String, type: TypeSyntax, settable: Bool)] = [:]
        var order: [String] = []
        for member in decl.memberBlock.members {
            // Members under `#if` may or may not be compiled: which, the
            // macro cannot know, and `Codable` codes those that are.
            if member.decl.is(IfConfigDeclSyntax.self) {
                throw Failure("@DagCBORCodable: members under #if are not supported")
            }
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  !variable.modifiers.contains(where: { ["static", "class"].contains($0.name.text) }) else { continue }
            let isLet = variable.bindingSpecifier.tokenKind == .keyword(.let)
            // `let a, b: T` gives both names the type of the last.
            var sharedType: TypeSyntax?
            var bindings: [(name: String, binding: PatternBindingSyntax, type: TypeSyntax?)] = []
            for binding in variable.bindings.reversed() {
                guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
                    throw Failure("@DagCBORCodable: a stored property must be a plain name")
                }
                if let type = binding.typeAnnotation?.type { sharedType = type }
                else if binding.initializer != nil || binding.accessorBlock != nil { sharedType = nil }
                bindings.insert((name, binding, binding.typeAnnotation?.type ?? sharedType), at: 0)
            }
            for (name, binding, type) in bindings {
                if let accessors = binding.accessorBlock, isComputed(accessors) { continue }
                // A wrapped property is coded as its wrapper, which the macro
                // does not see.
                guard variable.attributes.isEmpty else {
                    throw Failure("@DagCBORCodable: '\(name)' has an attribute (a property wrapper?), which is not supported")
                }
                guard let type else {
                    throw Failure("@DagCBORCodable: '\(name)' needs a type annotation")
                }
                guard !type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self) else {
                    throw Failure("@DagCBORCodable: '\(name)' is implicitly unwrapped; declare it optional")
                }
                // A `let` with a value is never read; one with no value is.
                stored[unescaped(name)] = (name, type, !(isLet && binding.initializer != nil))
                order.append(unescaped(name))
            }
        }

        var keyed: [(name: String, key: String)] = order.map { ($0, $0) }
        if let codingKeys = try declaredCodingKeys(of: decl) {
            keyed = try codingKeys.memberBlock.members
                .map { member in
                    // Only cases: `#if`, or a `stringValue` of its own, would
                    // key fields otherwise than the cases read.
                    guard let cases = member.decl.as(EnumCaseDeclSyntax.self) else {
                        throw Failure("@DagCBORCodable: CodingKeys may hold only cases")
                    }
                    return cases
                }
                .flatMap(\.elements)
                .map { element in
                    let name = unescaped(element.name.text)
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
            return Field(name: property.spelling, key: key, type: type, isOptional: isOptional)
        }
    }

    /// The struct's own `CodingKeys` enum, if its body declares one. Any
    /// other declaration of that name is refused.
    static func declaredCodingKeys(of decl: StructDeclSyntax) throws -> EnumDeclSyntax? {
        for member in decl.memberBlock.members {
            if let enumDecl = member.decl.as(EnumDeclSyntax.self), enumDecl.name.text == "CodingKeys" {
                return enumDecl
            }
            let named = member.decl.as(TypeAliasDeclSyntax.self)?.name.text
                ?? member.decl.as(StructDeclSyntax.self)?.name.text
                ?? member.decl.as(ClassDeclSyntax.self)?.name.text
            if named == "CodingKeys" {
                throw Failure("@DagCBORCodable: CodingKeys must be an enum of cases")
            }
        }
        return nil
    }

    /// `name` without the backticks that let a keyword be one.
    static func unescaped(_ name: String) -> String {
        name.hasPrefix("`") && name.hasSuffix("`") && name.count > 1 ? String(name.dropFirst().dropLast()) : name
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
