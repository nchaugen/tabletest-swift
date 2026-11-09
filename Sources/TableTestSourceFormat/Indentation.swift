/// One indent level: a number of spaces or tabs.
public struct Indentation: Equatable, Sendable {
    public enum Style: Sendable {
        case spaces
        case tabs
    }

    public let style: Style
    public let size: Int

    public init(style: Style, size: Int) {
        self.style = style
        self.size = size
    }
}
