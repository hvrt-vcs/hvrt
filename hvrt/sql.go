package hvrt

import (
	"embed"
	"fmt"
	"net/url"
	"strings"

	"github.com/uptrace/bun/driver/sqliteshim"
)

// SQL files for all operations for all supported DB dialects
//
//go:embed sql
var SQLFiles embed.FS

var SQLDialectToDrivers = map[string]string{
	"sqlite": sqliteshim.ShimName,
	// "postgresql": "postgresql",
	// "mysql":      "mysql",
}

func init() {
}

var SqliteDefaultOpts = map[string]string{
	"_foreign_keys":        "on",
	"_case_sensitive_like": "on",
	"mode":                 "rwc",
}

func SqliteDSN(path string, parms map[string]string) string {
	qparms := []string{}
	for key, val := range parms {
		qparms = append(qparms, fmt.Sprintf("%s=%s", key, val))
	}
	qstring := strings.Join(qparms, "&")
	dsn := fmt.Sprintf("%s?%s", path, url.QueryEscape(qstring))
	return dsn
}

func CopyOps(ops map[string]string) map[string]string {
	rmap := make(map[string]string)
	for key, val := range ops {
		rmap[key] = val
	}
	return rmap
}
