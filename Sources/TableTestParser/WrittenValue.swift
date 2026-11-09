/// A cell or an element as written in the source, apart from the whitespace around it.
///
/// A formatter prints this form, because it may change only whitespace (SPEC 4.1): quotes, a
/// repeated set element and the text of a map key stay as written. A test runner uses
/// ``TableValue`` instead.
package indirect enum WrittenValue: Equatable, Sendable {
    /// A blank cell.
    case blank
    /// A string, quoted or not, with its quotes.
    case text(String)
    case list([WrittenValue])
    /// Every element in source order, a repeated element included.
    case set([WrittenValue])
    case map([WrittenPair])
}

/// One key and value pair of a map, as written.
package struct WrittenPair: Equatable, Sendable {
    /// The key with its quotes, if it has any.
    package let key: String
    package let value: WrittenValue

    package init(key: String, value: WrittenValue) {
        self.key = key
        self.value = value
    }
}
