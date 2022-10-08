package hvrt

import (
	"database/sql"
	"fmt"
	_ "modernc.org/sqlite"
	"net/url"
	"os"
	"context"
	"path/filepath"
)

func Init(repo_file string) error {
	initScript, err := SQLFiles.ReadFile("sql/sqlite3/init.sql")
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

	sql_db, err := sql.Open("sqlite",
		fmt.Sprintf("%s?%s", repo_file, url.QueryEscape("_foreign_keys=1&_case_sensitive_like=1")),
	)
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
		return err
	}
	return tx.Commit()
}
