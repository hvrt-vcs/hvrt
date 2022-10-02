package hvrt

import (
  "embed"
// "modernc.org/sqlite"
)

// content is our static web server content.
//go:embed sql
var SQLFiles embed.FS

// init sets initial values for variables used in the package.
func init() {
  // fmt.Println(sql_files)
}
