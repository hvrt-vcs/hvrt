package hvrt

import (
	// "regexp"
	"errors"
	"log"
	"os"
	"path/filepath"
	"testing"
)

// TestHelloName calls greetings.Hello with a name, checking
// for a valid return value.
func TestInitLocalAll(t *testing.T) {
	testDir, err := os.MkdirTemp("", "*-testing")
	if err != nil {
		t.Fatalf(`Failed to create dummy test directory: %v`, err)
	}
	defer os.RemoveAll(testDir) // clean up
	log.Printf("Created temp directory: %s", testDir)

	repoFile := filepath.Join(testDir, ".hvrt/repo.hvrt")
	log.Printf("creating repo file: %s", repoFile)
	workTree := testDir
	defaultBranch := "trunk"
	// filepath.Join(testDir, "worktree")
	err = InitLocalAll(repoFile, workTree, defaultBranch)
	if err != nil {
		t.Fatalf(`Failed to init dummy repo due to error: %v`, err)
	}

	if _, err := os.Stat(repoFile); err == nil {
		// path/to/whatever exists
		log.Printf("repo file exists: %s", repoFile)
	} else if errors.Is(err, os.ErrNotExist) {
		// path/to/whatever does *not* exist
		t.Fatalf(`repo file not created: %v`, err)

	} else {
		// Schrodinger: file may or may not exist. See err for details.
		t.Fatalf(`Some weird error happened: %v`, err)
	}
}
