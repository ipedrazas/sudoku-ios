// The module path deliberately sits under sudoku-and-cake/backend/ so Go's
// internal-package rule lets this tool import internal/generator — the code
// being ported — without adding anything to the web repo.
module sudoku-and-cake/backend/tools/export-fixtures

go 1.25

require sudoku-and-cake/backend v0.0.0

replace sudoku-and-cake/backend => ../../../sudoku-and-cake/backend
