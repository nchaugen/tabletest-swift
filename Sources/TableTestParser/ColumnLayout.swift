/// How the columns of a table map to the parameters of a test function.
///
/// This is runner semantics, not parsing: both the macro, at compile time, and the runtime use
/// it, so that they accept the same tables.
public enum ColumnLayout: Sendable, Equatable {
    /// Every column maps to a parameter, in order.
    case parametersOnly
    /// The first column names the scenario of each row. The other columns map to the
    /// parameters, in order.
    case scenarioFirst

    /// The number of columns before the first parameter column.
    public var leadingColumns: Int {
        self == .scenarioFirst ? 1 : 0
    }
}

/// Why a table does not fit a test function, and where.
public struct TableFitError: Error, Sendable, Equatable {
    /// The 0-based index of the line in the input.
    public let line: Int
    /// The 0-based Unicode scalar offset on the line.
    public let column: Int
    public let message: String
}

extension Table {
    /// The layout that maps the table's columns to the parameters of a function.
    ///
    /// A table with one more column than parameters has a scenario column first. Every data
    /// row must have as many cells as the header row.
    public func columnLayout(parameterCount: Int) throws(TableFitError) -> ColumnLayout {
        let layout = try layoutOfHeader(parameterCount: parameterCount)
        try refuseRowsOfAnotherWidth()
        return layout
    }

    private func layoutOfHeader(parameterCount: Int) throws(TableFitError) -> ColumnLayout {
        switch header.cells.count {
        case parameterCount: return .parametersOnly
        case parameterCount + 1: return .scenarioFirst
        default:
            throw TableFitError(
                line: header.line,
                column: header.cells.first?.column ?? 0,
                message: "The table has \(counted(header.cells.count, "column")), but the function has "
                    + "\(counted(parameterCount, "parameter")): give it one parameter for each column, or for "
                    + "each column after a scenario column"
            )
        }
    }

    private func refuseRowsOfAnotherWidth() throws(TableFitError) {
        let width = header.cells.count
        guard let offset = rows.firstIndex(where: { $0.cells.count != width }) else {
            return
        }
        let row = rows[offset]
        throw TableFitError(
            line: row.line,
            column: row.cells.first?.column ?? 0,
            message: "Row \(offset + 1) has \(counted(row.cells.count, "cell")), but the header has \(width)"
        )
    }
}

/// `1 column`, `2 columns`.
private func counted(_ count: Int, _ noun: String) -> String {
    "\(count) \(noun)\(count == 1 ? "" : "s")"
}
