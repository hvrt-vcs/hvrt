package hvrt

import (
	"embed"
	"fmt"
	"net/url"
	"strings"
	// "modernc.org/sqlite"
)

// SQL files for all operations for all supported DB dialects
//
//go:embed sql
var SQLFiles embed.FS

func init() {
}

func SqliteDSN(path string, parms map[string]string) string {
	qparms := []string{}
	for key, val := range parms {
		qparms = append(qparms, fmt.Sprintf("%s=%s", key, val))
	}
	qstring := strings.Join(qparms, "&")
	return fmt.Sprintf("%s?%s", path, url.QueryEscape(qstring))
}
