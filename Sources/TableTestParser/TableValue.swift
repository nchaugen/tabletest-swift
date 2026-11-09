/// The value of one cell or one element, as the TableTest format defines it (SPEC chapter 2).
///
/// Equality follows the spec's "equal values": two sets, and two maps, are equal in any
/// order; two lists are equal only in the same order. Two strings are equal when they have
/// the same Unicode scalars, so `é` and `e` + U+0301 are different strings, as on the JVM.
public indirect enum TableValue: Hashable, Sendable {
    case string(String)
    /// The elements in source order.
    case list([TableValue])
    /// The elements in the order of first occurrence, with no duplicates.
    case set([TableValue])
    /// The entries in source order, with no duplicate keys.
    case map([TableMapEntry])
    /// The value of a blank cell.
    case null

    public static func == (lhs: TableValue, rhs: TableValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null):
            true
        case let (.string(left), .string(right)):
            left.hasSameScalars(as: right)
        case let (.list(left), .list(right)):
            left.elementsEqual(right)
        case let (.set(left), .set(right)):
            left.allSatisfy(right.contains) && right.allSatisfy(left.contains)
        case let (.map(left), .map(right)):
            left.allSatisfy(right.contains) && right.allSatisfy(left.contains)
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .null:
            hasher.combine(0)
        case let .string(text):
            hasher.combine(1)
            text.unicodeScalars.forEach { hasher.combine($0) }
        case let .list(elements):
            hasher.combine(2)
            elements.forEach { hasher.combine($0) }
        case let .set(elements):
            hasher.combine(3)
            hasher.combine(Set(elements.map(\.hashValue)).sorted())
        case let .map(entries):
            hasher.combine(4)
            hasher.combine(Set(entries.map(\.hashValue)).sorted())
        }
    }
}

/// One key and value pair of a map value.
public struct TableMapEntry: Hashable, Sendable {
    public let key: String
    public let value: TableValue

    public init(key: String, value: TableValue) {
        self.key = key
        self.value = value
    }

    public static func == (lhs: TableMapEntry, rhs: TableMapEntry) -> Bool {
        lhs.key.hasSameScalars(as: rhs.key) && lhs.value == rhs.value
    }

    public func hash(into hasher: inout Hasher) {
        key.unicodeScalars.forEach { hasher.combine($0) }
        hasher.combine(value)
    }
}

extension String {
    /// Compares scalar by scalar, not by canonical equivalence as `==` does.
    func hasSameScalars(as other: String) -> Bool {
        unicodeScalars.elementsEqual(other.unicodeScalars)
    }
}
