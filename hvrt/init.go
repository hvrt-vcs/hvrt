package hvrt

import (
  "database/sql"
  _ "modernc.org/sqlite"
)

// init sets initial values for variables used in the package.
func init() {
  sql_db, err := sql.Open("sqlite3", ":memory:")
  if err != nil {
    panic("Could not connect to sqlite database.")
  }
  // sql_db.Exec()
  // fmt.Println(sql_files)
}
