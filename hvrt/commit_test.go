package hvrt

import (
	// "context"

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

func setupCommitTests(t *testing.T, filename string, contents []byte) (string, string, string, Thunk) {
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

	dummyFile := filepath.Join(workTree, filename)
	err = os.WriteFile(dummyFile, contents, fs.FileMode(0777))
	if err != nil {
		t.Fatalf(`Failed to add dummy file due to error: %v`, err)
	}

	err = AddFiles(workTree, []string{filename})
	if err != nil {
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

	_, err := GetExistingLocalRepoDB(work_tree)
	if err != nil {
		t.Fatal(err)
	}
}
