package hvrt

import (
	"database/sql"
	"embed"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"strings"

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
	"sqlite":     sqliteshim.ShimName,
	"postgresql": "postgresql",
}

var WorkTreeDBName = "work_tree_state.sqlite"

func init() {
}

var SqliteDefaultOpts = map[string][]string{

	// FIXME: the modernc.org/sqlite implementation creates all connections and
	// read/write/create by default. It seems the "mode" parameter below is
	// completely ignored. A pragma value of `query_only(on)` will mostly get us
	// the behavior that we want though
	"mode": {"rwc"},

	// make transactions start with `BEGIN IMMEDIATE` instead of `BEGIN`. This
	// avoids deadlocks and busy errors at the expense of write speed. Should
	// not be a problem since the code is currently single threaded and
	// sequential.
	"_txlock": {"immediate"},

	// TODO: I'm not sure that mattn/sqlite respects a _pragma DSN parameter
	// like modernc.org/sqlite does. Try to reconcile this somehow.
	"_pragma": {"journal_mode(WAL)", "case_sensitive_like(on)", "foreign_keys(on)"},
}

func SqliteDSN(path string, parms map[string][]string) string {
	qparms := []string{}
	for key, vals := range parms {
		for _, v := range vals {
			qparms = append(qparms, fmt.Sprintf("%s=%s", key, v))
		}
	}
	qstring := strings.Join(qparms, "&")
	dsn := fmt.Sprintf("%s?%s", path, url.QueryEscape(qstring))
	return dsn
}

func CopyOps(ops map[string][]string) map[string][]string {
	rmap := make(map[string][]string)
	for key, val := range ops {
		val_copy := make([]string, len(val))
		copy(val_copy, val)
		rmap[key] = val_copy
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
	qparms["mode"] = []string{"rw"}

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

func GetRepoDBUri(work_tree string) (db_uri, db_type string, err error) {
	config_path := filepath.Join(work_tree, WorkTreeConfigDir, "config.toml")
	var conf HvrtConfig
	_, err = toml.DecodeFile(config_path, &conf)
	if err != nil {
		return "", "", err
	}
	log.Debug.Printf("toml data: %#v", conf)
	// log.Debug.Printf("toml metadata: %#v", md)

	db_type = conf.Worktree.Repo.Type
	if conf.Worktree.Repo.Type != "sqlite" {
		return "", "", fmt.Errorf("%w: cannot use database type other than sqlite", NotImplementedError)
	}

	varMap := map[string]string{
		"HVRT_WORK_TREE": work_tree,
	}
	db_uri = os.Expand(conf.Worktree.Repo.URI, func(s string) string { return varMap[s] })

	return db_uri, db_type, nil
}

type HvrtConfig struct {
	Worktree struct {
		Repo struct {
			Type string
			URI  string
		}
	}
}

func GetExistingRepoDB(work_tree string) (*sql.DB, error) {
	db_uri, db_type, err := GetRepoDBUri(work_tree)
	if err != nil {
		return nil, err
	}
	db_uri = strings.TrimPrefix(db_uri, "file://")

	qparms := CopyOps(SqliteDefaultOpts)

	// The default mode is "rwc", which will create the file if it doesn't
	// already exist. This is NOT what we want. We want to fail loudly if the
	// file does not exist already.
	qparms["mode"] = []string{"rw"}

	// work tree state is always sqlite
	wt_db, err := sql.Open(SQLDialectToDrivers[db_type], SqliteDSN(db_uri, qparms))
	if err != nil {
		return nil, err
	}

	// sqlite will not throw an error regarding a DB file not exising until we
	// actually attempt to interact with the database, so we need to explicitly
	// check whether it exists. We do this after opening the database connection
	// to avoid a race condition where someone else could delete the file
	// between our existence check and the opening of the connection.
	if _, err = os.Stat(db_uri); err != nil {
		wt_db.Close()
		return nil, err
	}

	return wt_db, nil
}
