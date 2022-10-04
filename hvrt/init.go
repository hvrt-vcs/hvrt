package hvrt

import (
  "fmt"
  "database/sql"
  _ "modernc.org/sqlite"
)

// init sets initial values for variables used in the package.
func init() {
  sql_db, err := sql.Open("sqlite3", ":memory:")
  if err != nil {
    panic("Could not connect to sqlite database.")
  }
  defer sql_db.Close()
  fmt.Println("Did we load the SQL DB?", sql_db)

  initScript, err := sql_files.ReadFile("sql/sqlite3/init.sql")
  if err != nil {
    fmt.Println("We screwed up somehow:", err)
    panic("Chickening out...")
  }
  fmt.Println("Did we load the init script?", initScript)
  sql_db.Exec(string(initScript))
  // fmt.Println(sql_files)
}
