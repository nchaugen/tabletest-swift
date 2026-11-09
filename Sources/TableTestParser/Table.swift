/// A parsed table: one header row and its data rows, in source order.
public struct Table: Sendable {
    public let header: Row
    public let rows: [Row]

    /// The value of each header cell.
    public var headers: [TableValue] {
        header.cells.map(\.value)
    }
}

/// One row of a table and where it is in the input.
public struct Row: Sendable {
    /// The 0-based index of the row's line in the input. Blank lines and comment lines count.
    public let line: Int
    public let cells: [Cell]

    /// The value of each cell.
    public var values: [TableValue] {
        cells.map(\.value)
    }
}

/// One cell of a row and where it starts on its line.
public struct Cell: Sendable {
    public let value: TableValue
    /// The 0-based Unicode scalar offset of the cell's first character that is not whitespace.
    /// For a blank cell, the offset of the `|` or the line end that closes it.
    public let column: Int
}
