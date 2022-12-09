package hvrt

import (
	// "regexp"
	"errors"
	"log"
	"os"
	"path/filepath"
	"testing"
)

// TODO: move boiler plate test init into a function with the signature: func (t *testing.T) (string, Thunk) {}
// The Thunk is the cleanup function that should be immediatly deferred and the
// string is the temp directory. Function is allowed to panic.

func TestInitLocalAllCreatesRepoDB(t *testing.T) {
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

	err = InitLocalAll(repoFile, workTree, defaultBranch)
	if err != nil {
		t.Fatalf(`Failed to init dummy repo due to error: %v`, err)
	}

	if _, err := os.Stat(repoFile); err == nil {
		log.Printf("repo file exists: %s", repoFile)
	} else if errors.Is(err, os.ErrNotExist) {
		t.Fatalf(`repo file not created: %v`, err)
	} else {
		// Schrodinger: file may or may not exist. See err for details.
		t.Fatalf(`Some weird error happened: %v`, err)
	}
}

func TestInitLocalAllCreatesWorktreeDB(t *testing.T) {
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

	err = InitLocalAll(repoFile, workTree, defaultBranch)
	if err != nil {
		t.Fatalf(`Failed to init dummy repo due to error: %v`, err)
	}
	worktreeDB := filepath.Join(testDir, ".hvrt/work_tree_state.sqlite")

	if _, err := os.Stat(worktreeDB); err == nil {
		log.Printf("worktree database file exists: %s", worktreeDB)
	} else if errors.Is(err, os.ErrNotExist) {
		t.Fatalf(`worktree database file not created: %v`, err)
	} else {
		// Schrodinger: file may or may not exist. See err for details.
		t.Fatalf(`Some weird error happened: %v`, err)
	}
}

func TestInitLocalAllCreatesWorktreeConfig(t *testing.T) {
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
	configFile := filepath.Join(testDir, ".hvrt/config.toml")

	if _, err := os.Stat(configFile); err == nil {
		log.Printf("worktree config file exists: %s", configFile)
	} else if errors.Is(err, os.ErrNotExist) {
		t.Fatalf(`worktree config file not created: %v`, err)
	} else {
		// Schrodinger: file may or may not exist. See err for details.
		t.Fatalf(`Some weird error happened: %v`, err)
	}
}
