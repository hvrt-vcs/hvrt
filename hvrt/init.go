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

func prepError(tx_err error) error {
	matched, _ := regexp.MatchString(
		`table vcs_version already exists`,
		tx_err.Error(),
	)
	if matched {
		tx_err = errors.New("Repo already initialized")
	}
	return tx_err
}

func Init(repo_file string) error {
	dbtype := "sqlite"
	repo_script_path := fmt.Sprintf("sql/%s/repo/init.sql", dbtype)

	// work tree state is always sqlite
	work_tree_script_path := "sql/sqlite/work_tree/init.sql"
	qparms := CopyOps(SqliteDefaultOpts)
	repo_script, err := SQLFiles.ReadFile(repo_script_path)
	if err != nil {
		return err
	}
	repo_string := string(repo_script)

	work_tree_script, err := SQLFiles.ReadFile(work_tree_script_path)
	if err != nil {
		return err
	}
	work_tree_string := string(work_tree_script)

	// create parent directories to file if they do not already exist
	par_dir := filepath.Dir(repo_file)
	err = os.MkdirAll(par_dir, 0775)
	if err != nil {
		return err
	}
	work_tree_file := filepath.Join(par_dir, "work_tree_state.sqlite")

	repo_db, err := sql.Open(dbtype, SqliteDSN(repo_file, qparms))
	if err != nil {
		return err
	}
	defer repo_db.Close()

	wt_db, err := sql.Open("sqlite", SqliteDSN(work_tree_file, qparms))
	if err != nil {
		return err
	}
	defer wt_db.Close()

	repo_tx, err := repo_db.BeginTx(context.Background(), nil)
	if err != nil {
		return err
	}

	wt_tx, err := wt_db.BeginTx(context.Background(), nil)
	if err != nil {
		return err
	}

	_, err = repo_tx.Exec(repo_string, SemanticVersion)
	if err != nil {
		// Ignore rollback errors, for now.
		_ = repo_tx.Rollback()
		return prepError(err)
	}

	_, err = wt_tx.Exec(work_tree_string, SemanticVersion)
	if err != nil {
		// Ignore rollback errors, for now.
		_ = repo_tx.Rollback()
		_ = wt_tx.Rollback()
		return prepError(err)
	}
	wt_tx.Commit()
	return repo_tx.Commit()

	// TODO: create config.toml file.
}
