package hvrt

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	_ "modernc.org/sqlite"
	"os"
	"path/filepath"
	"regexp"
)

func Init(repo_file string) error {
	dbtype := "sqlite"
	script_path := fmt.Sprintf("sql/%s/init.sql", dbtype)
	qparms := map[string]string{
		"_foreign_keys":        "on",
		"_case_sensitive_like": "on",
	}
	initScript, err := SQLFiles.ReadFile(script_path)
	if err != nil {
		return err
	}
	initString := string(initScript)

	// create parent directories to file if they do not already exist
	par_dir := filepath.Dir(repo_file)
	err = os.MkdirAll(par_dir, 0775)
	if err != nil {
		return err
	}

	sql_db, err := sql.Open(dbtype, SqliteDSN(repo_file, qparms))
	if err != nil {
		return err
	}
	defer sql_db.Close()

	tx, err := sql_db.BeginTx(context.Background(), nil)
	if err != nil {
		return err
	}

	_, err = tx.Exec(initString, SemanticVersion)
	if err != nil {
		// Ignore rollback errors, for now.
		_ = tx.Rollback()
		matched, _ := regexp.MatchString(
			`table vcs_version already exists`,
			err.Error(),
		)
		if matched {
			err = errors.New("Repo already initialized")
		}
		return err
	}
	return tx.Commit()

	// TODO: create config.toml file.
}
