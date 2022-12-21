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

func setupAddTests(t *testing.T) (string, string, string, Thunk) {
	workTree, err := os.MkdirTemp("", "*-testing")
	if err != nil {
		t.Fatalf(`Failed to create dummy test directory: %v`, err)
	}
	cleanupFunc := func() { os.RemoveAll(workTree) }
	log.Printf("Created temp directory: %s", workTree)

	repoFile := filepath.Join(workTree, WorkTreeConfigDir, "repo.hvrt")
	log.Printf("creating repo file: %s", repoFile)
	defaultBranch := "trunk"

	err = InitLocalAll(repoFile, workTree, defaultBranch)
	if err != nil {
		cleanupFunc()
		t.Fatalf(`Failed to init dummy repo due to error: %v`, err)
	}

	dummyFile := filepath.Join(workTree, "dummy_file.txt")
	err = os.WriteFile(dummyFile, []byte("Blah blah blah"), fs.FileMode(0777))
	if err != nil {
		t.Fatalf(`Failed to add dummy file due to error: %v`, err)
	}

	err = AddFiles(workTree, []string{"dummy_file.txt"})
	if err != nil {
		t.Fatalf(`Failed to add dummy file due to error: %v`, err)
	}

	work_tree_file := filepath.Join(workTree, WorkTreeConfigDir, "work_tree_state.sqlite")

	return workTree, work_tree_file, defaultBranch, cleanupFunc
}

func TestAddFileToWorktreeDB(t *testing.T) {
	_, work_tree_file, _, cleanupFunc := setupAddTests(t)
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
		} else if path != "dummy_file.txt" {
			t.Fatalf(`Row is not "dummy_file.txt" %v`, path)
		}
		log.Println("sqlite worktree DB row:", path, hash, hash_algo, size, created_at)
	}

	if !found_something {
		t.Fatalf(`We aren't iterating thru any rows: %v`, rows)
	}
}
