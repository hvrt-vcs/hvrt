package hvrt

import (
	// "regexp"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/hvrt-vcs/hvrt/log"
)

func init() {
	log.SetLoggingLevel(0)
}

func setupInitTests(t *testing.T) (string, string, string, Thunk) {
	workTree, err := os.MkdirTemp("", "*-testing")
	if err != nil {
		t.Fatalf(`Failed to create dummy test directory: %v`, err)
	}
	cleanupFunc := func() { os.RemoveAll(workTree) }
	log.Info.Printf("Created temp directory: %s", workTree)

	repoFile := filepath.Join(workTree, ".hvrt/repo.hvrt")
	log.Info.Printf("creating repo file: %s", repoFile)
	defaultBranch := "trunk"

	err = InitLocalAll(repoFile, workTree, defaultBranch)
	if err != nil {
		cleanupFunc()
		t.Fatalf(`Failed to init dummy repo due to error: %v`, err)
	}

	return workTree, repoFile, defaultBranch, cleanupFunc
}

func TestInitLocalAllCreatesRepoDB(t *testing.T) {
	_, repoFile, _, cleanupFunc := setupInitTests(t)
	defer cleanupFunc()

	if _, err := os.Stat(repoFile); err == nil {
		log.Info.Printf("repo file exists: %s", repoFile)
	} else if errors.Is(err, os.ErrNotExist) {
		t.Fatalf(`repo file not created: %v`, err)
	} else {
		// Schrodinger: file may or may not exist. See err for details.
		t.Fatalf(`Some weird error happened: %v`, err)
	}
}

func TestInitLocalAllCreatesWorktreeDB(t *testing.T) {
	workTree, _, _, cleanupFunc := setupInitTests(t)
	defer cleanupFunc()

	worktreeDB := filepath.Join(workTree, ".hvrt/work_tree_state.sqlite")

	if _, err := os.Stat(worktreeDB); err == nil {
		log.Info.Printf("worktree database file exists: %s", worktreeDB)
	} else if errors.Is(err, os.ErrNotExist) {
		t.Fatalf(`worktree database file not created: %v`, err)
	} else {
		// Schrodinger: file may or may not exist. See err for details.
		t.Fatalf(`Some weird error happened: %v`, err)
	}
}

func TestInitLocalAllCreatesWorktreeConfig(t *testing.T) {
	workTree, _, _, cleanupFunc := setupInitTests(t)
	defer cleanupFunc()

	configFile := filepath.Join(workTree, ".hvrt/config.toml")

	if _, err := os.Stat(configFile); err == nil {
		log.Info.Printf("worktree config file exists: %s", configFile)
	} else if errors.Is(err, os.ErrNotExist) {
		t.Fatalf(`worktree config file not created: %v`, err)
	} else {
		// Schrodinger: file may or may not exist. See err for details.
		t.Fatalf(`Some weird error happened: %v`, err)
	}
}
