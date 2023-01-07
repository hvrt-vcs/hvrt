package hvrt

import (
	// "context"
	"database/sql"
	"io/fs"

	// "errors"
	// "fmt"
	// "github.com/klauspost/compress/zstd"

	// "os"

	// "regexp"

	"log"
	"os"
	"path/filepath"
	"testing"
)

func setupAddTests(t *testing.T, filename string, contents []byte) (string, string, string, Thunk) {
	cwd, err := os.Getwd()
	if err != nil {
		t.Fatalf(`Failed to init dummy repo due to error: %v`, err)
	}

	workTree, err := os.MkdirTemp("", "*-testing")
	if err != nil {
		t.Fatalf(`Failed to create dummy test directory: %v`, err)
	}
	log.Printf("Created temp directory: %s", workTree)

	err = os.Chdir(workTree)
	if err != nil {
		os.RemoveAll(workTree)
		t.Fatalf(`Failed to init dummy repo due to error: %v`, err)
	}

	cleanupFunc := func() {
		_ = os.Chdir(cwd)
		os.RemoveAll(workTree)
	}

	repoFile := filepath.Join(workTree, WorkTreeConfigDir, "repo.hvrt")
	log.Printf("creating repo file: %s", repoFile)
	defaultBranch := "trunk"

	err = InitLocalAll(repoFile, workTree, defaultBranch)
	if err != nil {
		cleanupFunc()
		t.Fatalf(`Failed to init dummy repo due to error: %v`, err)
	}

	dummyFile := filepath.Join(workTree, filename)
	log.Printf("creating dummy file: %s", dummyFile)
	err = os.WriteFile(dummyFile, contents, fs.FileMode(0777))
	if err != nil {
		cleanupFunc()
		t.Fatalf(`Failed to add dummy file due to error: %v`, err)
	}

	err = AddFiles(workTree, []string{filename})
	if err != nil {
		cleanupFunc()
		t.Fatalf(`Failed to add dummy file due to error: %v`, err)
	}

	work_tree_file := filepath.Join(workTree, WorkTreeConfigDir, "work_tree_state.sqlite")

	return workTree, work_tree_file, defaultBranch, cleanupFunc
}

func TestAddFileToWorktreeDB(t *testing.T) {
	filename := "dummy_file.txt"
	contents := []byte("blah blah blah")
	_, work_tree_file, _, cleanupFunc := setupAddTests(t, filename, contents)
	defer cleanupFunc()

	// work tree state is always sqlite
	qparms := CopyOps(SqliteDefaultOpts)
	wt_db, err := sql.Open(SQLDialectToDrivers["sqlite"], SqliteDSN(work_tree_file, qparms))
	if err != nil {
		t.Fatalf(`Failed to add dummy file due to error: %v`, err)
	}
	defer wt_db.Close()

	rows, err := wt_db.Query("SELECT * from staged_to_add")
	if err != nil {
		t.Fatalf(`Failed to retrieve SQL rows due to error: %v`, err)
	}
	defer rows.Close()

	var path, hash, hash_algo string
	var size, created_at int
	var found_something bool = false

	for rows.Next() {
		found_something = true
		err := rows.Scan(&path, &hash, &hash_algo, &size, &created_at)
		if err != nil {
			t.Fatalf(`Failed to retrieve SQL row due to error: %v`, err)
		} else if path != filename {
			t.Fatalf(`Row is not "%v": "%v"`, filename, path)
		}
		log.Println("sqlite worktree DB row:", path, hash, hash_algo, size, created_at)
	}

	if !found_something {
		t.Fatalf(`We aren't iterating thru any rows: %v`, rows)
	}
}

func TestAddEmptyFileToWorktreeDB(t *testing.T) {
	filename := "empty.txt"
	contents := []byte("")
	_, work_tree_file, _, cleanupFunc := setupAddTests(t, filename, contents)
	defer cleanupFunc()

	// work tree state is always sqlite
	qparms := CopyOps(SqliteDefaultOpts)
	wt_db, err := sql.Open(SQLDialectToDrivers["sqlite"], SqliteDSN(work_tree_file, qparms))
	if err != nil {
		t.Fatalf(`Failed to add dummy file due to error: %v`, err)
	}
	defer wt_db.Close()

	rows, err := wt_db.Query("SELECT * from staged_to_add")
	if err != nil {
		t.Fatalf(`Failed to retrieve SQL rows due to error: %v`, err)
	}
	defer rows.Close()

	var path, hash, hash_algo string
	var size, created_at int
	var found_something bool = false

	for rows.Next() {
		found_something = true
		err := rows.Scan(&path, &hash, &hash_algo, &size, &created_at)
		if err != nil {
			t.Fatalf(`Failed to retrieve SQL row due to error: %v`, err)
		} else if path != filename {
			t.Fatalf(`Row is not "%v": "%v"`, filename, path)
		} else if size != 0 {
			t.Fatalf(`File "%v" is not zero bytes long`, filename)
		}
		log.Println("sqlite worktree DB row:", path, hash, hash_algo, size, created_at)
	}

	if !found_something {
		t.Fatalf(`We aren't iterating thru any rows: %v`, rows)
	}

	// TODO: check that no chunks were written to the database. A zero sized
	// file should have no chunks.
}
