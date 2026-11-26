@_exported import DagCBORKit

/// Writes a struct's ``DagCBORKit/DagCBORCodable`` conformance from its
/// stored properties: the bytes and verdicts its synthesized `Codable`
/// conformance gives, in one pass.
///
/// - Each property is a map entry, keyed by its name, or by its `CodingKeys`
///   raw value when the struct declares `CodingKeys` (which then also lists
///   the properties coded); it must be an enum of plain cases. When the body
///   declares none, the macro declares it, so `Codable` keys the same fields
///   and a `CodingKeys` elsewhere fails to compile. Entries are in canonical
///   key order, worked out when compiling.
/// - Property wrappers, implicitly unwrapped optionals and members under
///   `#if` are refused, as the macro cannot write what `Codable` writes for
///   them.
/// - An optional property is absent when `nil`, as `encodeIfPresent` writes
///   it. Every other property's type must be `DagCBORCodable`.
/// - Once every field is read, the reader calls `checkDagCBORFields()`, for
///   a rule the type's `init(from:)` applies to the fields together.
@attached(member, names: named(CodingKeys))
@attached(extension, conformances: DagCBORCodable, names: named(init(dagCBOR:)), named(writeDagCBOR(to:)))
public macro DagCBORCodable() = #externalMacro(module: "DagCBORMacroPlugin", type: "DagCBORCodableMacro")
