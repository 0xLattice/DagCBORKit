@_exported import DagCBORKit

/// Writes a struct's ``DagCBORKit/DagCBORCodable`` and `Codable`
/// conformances from one list of its stored properties, so the two encode
/// alike: one field list, one set of keys, one rule.
///
/// - Each property is a map entry, keyed by its name, or by its `CodingKeys`
///   raw value when the struct declares `CodingKeys` in its body (an enum of
///   plain cases, which then also lists the properties coded). DAG-CBOR
///   entries are in canonical key order, worked out when compiling.
/// - An optional property is absent when `nil`.
/// - `init(from:)` and `init(dagCBOR:)` both call `checkDagCBORFields()` once
///   every field is read, for a rule over the fields together; `init(from:)`
///   first calls `checkDecoding(from:)`, for a rule over the input itself.
/// - The struct declares no `encode(to:)` or `init(from:)` of its own (they
///   would be redeclarations). Property wrappers, implicitly unwrapped
///   optionals and members under `#if` are refused.
@attached(
    extension,
    conformances: DagCBORCodable, Encodable, Decodable,
    names: named(init(from:)), named(encode(to:)), named(init(dagCBOR:)), named(writeDagCBOR(to:))
)
public macro DagCBORCodable() = #externalMacro(module: "DagCBORMacroPlugin", type: "DagCBORCodableMacro")
