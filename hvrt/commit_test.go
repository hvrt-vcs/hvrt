package hvrt

import (
	// "context"

	"io/fs"

	// "errors"
	// "fmt"
	// "github.com/klauspost/compress/zstd"

	// "os"

	// "regexp"

	"os"
	"path/filepath"
	"testing"

	"github.com/hvrt-vcs/hvrt/log"
)

func init() {
	log.SetLoggingLevel(0)
}

func setupCommitTests(t *testing.T, filename string, contents []byte) (string, string, string, Thunk) {
	cwd, err := os.Getwd()
	if err != nil {
		t.Fatalf(`Failed to init dummy repo due to error: %v`, err)
	}

	workTree, err := os.MkdirTemp("", "*-testing")
	if err != nil {
		t.Fatalf(`Failed to create dummy test directory: %v`, err)
	}
	log.Info.Printf("Created temp directory: %s", workTree)

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
	log.Info.Printf("creating repo file: %s", repoFile)
	defaultBranch := "trunk"

	err = InitLocalAll(repoFile, workTree, defaultBranch)
	if err != nil {
		cleanupFunc()
		t.Fatalf(`Failed to init dummy repo due to error: %v`, err)
	}

	dummyFile := filepath.Join(workTree, filename)
	log.Info.Printf("creating dummy file: %s", dummyFile)
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

func TestAddFileToLocalRepoDB(t *testing.T) {
	filename := "dummy_file.txt"
	contents := []byte("blah blah blah")
	work_tree, _, _, cleanupFunc := setupCommitTests(t, filename, contents)
	defer cleanupFunc()

	err := Commit(work_tree, "This is important; this means something.", "email@example.com", "")
	if err != nil {
		t.Fatal(err)
	}

	repo_db, err := GetExistingRepoDB(work_tree)
	if err != nil {
		t.Fatal(err)
	}
	defer repo_db.Close()

	log.Debug.Println(repo_db)
}
