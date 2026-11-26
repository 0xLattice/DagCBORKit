# DagCBORKit

Reading and writing [DAG-CBOR](https://ipld.io/specs/codecs/dag-cbor/spec/) in its one canonical form, in a single pass, without `Codable`.

A value's content address is the hash of its encoding, so each value must have exactly one encoding. DagCBORKit keeps that guarantee with one rule: `DagCBORCanonical.decode` accepts bytes only if writing the decoded value gives back exactly those bytes. Trailing bytes, wider-than-needed integer heads, map keys out of order, repeated or unknown keys, and a `null` where a field is absent all fail that comparison. A reader therefore only has to read correctly. It never has to detect a second spelling itself.

## Products

- **`DagCBORKit`**: the `DagCBORCodable` protocol, `DagCBORReader`, `DagCBORWriter`, `DagCBORCanonical` (the rule and the canonical key order), and conformances for `String`, `Bool`, the fixed-width integers, arrays, and `String`-backed enums. It has no dependencies.
- **`DagCBORMacro`**: `@DagCBORCodable`, which writes a struct's conformance from its stored properties. It builds swift-syntax, so depend on it only where you use the macro.

## The macro

```swift
import DagCBORMacro

@DagCBORCodable
struct Entry {
    let height: UInt64
    let note: String?      // absent when nil
    let kind: Kind         // any DagCBORCodable type

    enum CodingKeys: String, CodingKey {
        case height, note
        case kind = "k"    // keys come from CodingKeys when declared
    }
}
```

- Each coded property is one map entry, written in canonical key order (shorter keys first, then bytewise). The order is worked out when compiling, and the generated code is plain field-by-field reads and writes.
- These are the bytes a synthesized `Codable` conformance produces under a canonical DAG-CBOR encoder, so a type can have both conformances and a value keeps one CID whichever path wrote it.
- For a rule over the fields together (one `init(from:)` applies after decoding), implement `func checkDagCBORFields() throws`. The generated reader calls it once every field is read.
