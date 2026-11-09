# tabletest-swift

TableTest for Swift: tables of test data in plain text, for Swift Testing.

**Status:** unpublished, in development.

This package implements the TableTest format that `tabletest-spec` defines. The first
target is `TableTestParser`, a parser with no dependencies.

## Conformance fixtures

`Tests/TableTestParserTests/Fixtures/parse/` holds a copy of the parse fixtures of
`tabletest-spec`, and `Tests/TableTestTests/Fixtures/run/` a copy of its run fixtures.
`Fixtures/SPEC_COMMIT` in each names the spec commit of the copy. To update both copies
from a `tabletest-spec` checkout beside this repo:

```sh
scripts/sync-fixtures.sh
```
