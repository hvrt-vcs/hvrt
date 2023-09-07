package hvrt

import (
	"context"
	"database/sql"
	_ "embed"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"

	"github.com/uptrace/bun/driver/sqliteshim"
)

//go:embed default.toml
var initConfigTemplate string

func prepError(tx_err error) error {
	matched, _ := regexp.MatchString(
		`table vcs_version already exists`,
		tx_err.Error(),
	)
	if matched {
		tx_err = errors.New("repo already initialized")
	}
	return tx_err
}

func InitWorkTreeConfig(work_tree string, inner_thunk ThunkErr) error {
	work_tree_file := filepath.Join(work_tree, WorkTreeConfigDir, "config.toml")

	f, err := os.OpenFile(work_tree_file, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0644)
	if err != nil {
		return err
	}
	defer f.Close()

	_, err = f.WriteString(initConfigTemplate)
	if err != nil {
		f.Close()
		os.Remove(work_tree_file)
		return err
	}

	err = inner_thunk()
	if err != nil {
		f.Close()
		os.Remove(work_tree_file)
		return err
	}

	return nil
}

func InitWorkTree(work_tree, default_branch string, inner_thunk ThunkErr) error {
	work_tree_file := GetWorktreeDBPath(work_tree)
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
	wt_db, err := sql.Open(SQLDialectToDrivers["sqlite"], SqliteDSN(work_tree_file, qparms))
	if err != nil {
		return err
	}
	defer wt_db.Close()

	wt_tx, err := wt_db.BeginTx(context.Background(), nil)
	if err != nil {
		return err
	}

	_, err = wt_tx.Exec(work_tree_string, BareVersion, default_branch)
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

	repo_db, err := sql.Open(SQLDialectToDrivers[dbtype], SqliteDSN(repo_file, qparms))
	if err != nil {
		return err
	}
	defer repo_db.Close()

	repo_tx, err := repo_db.BeginTx(context.Background(), nil)
	if err != nil {
		return err
	}

	_, err = repo_tx.Exec(repo_string, BareVersion, default_branch)
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
}

func InitLocalAll(repo_file, work_tree, default_branch string) error {
	return InitLocal(
		repo_file,
		default_branch,
		func() error {
			return InitWorkTree(
				work_tree,
				default_branch,
				func() error {
					return InitWorkTreeConfig(
						work_tree,
						NilThunkErr,
					)
				},
			)
		},
	)
}

var FSError = errors.New("Could not initialize due to issue with error")

func (hs *HavartiState) InitLocalAll(default_branch string) error {
	if hs.workTreeFS == nil {
		return fmt.Errorf("worktree FS is nil: %w", FSError)
	}

	if hs.workTree == nil {
		return errors.New("HavartiState worktree is nil")
	}

	dsn_url, err := hs.GetDSN()
	if err != nil {
		return err
	}

	switch hs._DBDriverName {
	case sqliteshim.ShimName:
		InitLocalAll(dsn_url.Path, *hs.workTree, default_branch)
	}

	return InitLocalAll(dsn_url.Path, *hs.workTree, default_branch)
}
