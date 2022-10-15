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

func InitWorkTree(work_tree, default_branch string, inner_thunk ThunkErr) error {
	work_tree_file := filepath.Join(work_tree, WorkTreeConfigDir, "work_tree_state.sqlite")
	work_tree_script_path := "sql/sqlite/work_tree/init.sql"
	qparms := CopyOps(SqliteDefaultOpts)

	work_tree_script, err := SQLFiles.ReadFile(work_tree_script_path)
	if err != nil {
		return err
	}
	work_tree_string := string(work_tree_script)

	// create parent directories to file if they do not already exist
	par_dir := filepath.Dir(work_tree_file)
	err = os.MkdirAll(par_dir, 0775)
	if err != nil {
		return err
	}

	// work tree state is always sqlite
	wt_db, err := sql.Open("sqlite", SqliteDSN(work_tree_file, qparms))
	if err != nil {
		return err
	}
	defer wt_db.Close()

	wt_tx, err := wt_db.BeginTx(context.Background(), nil)
	if err != nil {
		return err
	}

	_, err = wt_tx.Exec(work_tree_string, SemanticVersion, default_branch)
	if err != nil {
		// Ignore rollback errors, for now.
		_ = wt_tx.Rollback()
		return prepError(err)
	}

	err = inner_thunk()
	if err != nil {
		// Ignore rollback errors, for now.
		_ = wt_tx.Rollback()
		return prepError(err)
	}
	return wt_tx.Commit()
}

func InitLocal(repo_file, default_branch string, inner_thunk ThunkErr) error {
	dbtype := "sqlite"
	repo_script_path := fmt.Sprintf("sql/%s/repo/init.sql", dbtype)

	qparms := CopyOps(SqliteDefaultOpts)
	repo_script, err := SQLFiles.ReadFile(repo_script_path)
	if err != nil {
		return err
	}
	repo_string := string(repo_script)

	// create parent directories to file if they do not already exist
	par_dir := filepath.Dir(repo_file)
	err = os.MkdirAll(par_dir, 0775)
	if err != nil {
		return err
	}

	repo_db, err := sql.Open(dbtype, SqliteDSN(repo_file, qparms))
	if err != nil {
		return err
	}
	defer repo_db.Close()

	repo_tx, err := repo_db.BeginTx(context.Background(), nil)
	if err != nil {
		return err
	}

	_, err = repo_tx.Exec(repo_string, SemanticVersion, default_branch)
	if err != nil {
		// Ignore rollback errors, for now.
		_ = repo_tx.Rollback()
		return prepError(err)
	}

	err = inner_thunk()
	if err != nil {
		// Ignore rollback errors, for now.
		_ = repo_tx.Rollback()
		return prepError(err)
	}
	return repo_tx.Commit()

	// TODO: create config.toml file.
}

func InitLocalAll(repo_file, work_tree, default_branch string) error {
	return InitLocal(
		repo_file,
		default_branch,
		// add creation of toml config here as the deepest layer
		func() error { return InitWorkTree(work_tree, default_branch, NilThunkErr) },
	)
}
