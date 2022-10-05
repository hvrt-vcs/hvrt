package hvrt

import (
	"embed"
	// "modernc.org/sqlite"
)

// SQL files for all operations for all supported DB dialects
//
//go:embed sql
var SQLFiles embed.FS

func init() {
}
