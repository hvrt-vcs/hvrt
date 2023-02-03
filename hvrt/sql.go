package hvrt

import (
	"database/sql"
	"embed"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/BurntSushi/toml"
	"github.com/hvrt-vcs/hvrt/log"

	// toml "github.com/pelletier/go-toml/v2"

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

var WorkTreeDBName = "work_tree_state.sqlite"

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

func GetWorktreeDBPath(work_tree string) string {
	return filepath.Join(work_tree, WorkTreeConfigDir, WorkTreeDBName)
}

func GetExistingWorktreeDB(work_tree string) (*sql.DB, error) {
	work_tree_file := GetWorktreeDBPath(work_tree)
	qparms := CopyOps(SqliteDefaultOpts)

	// The default mode is "rwc", which will create the file if it doesn't
	// already exist. This is NOT what we want. We want to fail loudly if the
	// file does not exist already.
	qparms["mode"] = "rw"

	// work tree state is always sqlite
	wt_db, err := sql.Open(SQLDialectToDrivers["sqlite"], SqliteDSN(work_tree_file, qparms))
	if err != nil {
		return nil, err
	}

	// sqlite will not throw an error regarding a DB file not exising until we
	// actually attempt to interact with the database, so we need to explicitly
	// check whether it exists. We do this after opening the database connection
	// to avoid a race condition where someone else could delete the file
	// between our existence check and the opening of the connection.
	if _, err = os.Stat(work_tree_file); err != nil {
		wt_db.Close()
		return nil, err
	}

	return wt_db, nil
}

type HvrtConfig struct {
	Age        int
	Cats       []string
	Pi         float64
	Perfection []int
	DOB        time.Time
}

func GetExistingLocalRepoDB(work_tree string) (*sql.DB, error) {
	config_path := filepath.Join(work_tree, WorkTreeConfigDir, "config.toml")
	var conf HvrtConfig
	md, err := toml.DecodeFile(config_path, &conf)
	if err != nil {
		return nil, err
	}
	log.Debug.Printf("toml metadata: %v", md)
	return nil, fmt.Errorf("toml test")

	work_tree_file := GetWorktreeDBPath(work_tree)
	qparms := CopyOps(SqliteDefaultOpts)

	// The default mode is "rwc", which will create the file if it doesn't
	// already exist. This is NOT what we want. We want to fail loudly if the
	// file does not exist already.
	qparms["mode"] = "rw"

	// work tree state is always sqlite
	wt_db, err := sql.Open(SQLDialectToDrivers["sqlite"], SqliteDSN(work_tree_file, qparms))
	if err != nil {
		return nil, err
	}

	// sqlite will not throw an error regarding a DB file not exising until we
	// actually attempt to interact with the database, so we need to explicitly
	// check whether it exists. We do this after opening the database connection
	// to avoid a race condition where someone else could delete the file
	// between our existence check and the opening of the connection.
	if _, err = os.Stat(work_tree_file); err != nil {
		wt_db.Close()
		return nil, err
	}

	return wt_db, nil
}
