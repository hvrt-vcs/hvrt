package hvrt

import (
	"database/sql"
	"errors"
	"fmt"
	"io/fs"
	"os"
)

type Thunk func()
type ThunkErr func() error
type ThunkAny func() any

func NilThunk()          {}
func NilThunkErr() error { return nil }
func NilThunkAny() any   { return nil }

const (
	WorkTreeConfigDir = ".hvrt"
)

var (
	NotImplementedError error = errors.New("feature not yet implemented")
	MissingDSNError     error = errors.New("DSN is empty")
)

// Struct definition that contains all state required to run an instance of Havarti
type HavartiState struct {
	// FS to interact with for worktree. May be nil or readonly
	workTreeFS fs.FS

	// String to the original working directory
	originalWorkDir *string

	// The directory in which the worktree is located. May be nil
	workTree *string

	// the base URI to connect to database
	dataSourceName string

	// Driver name for repository DB
	_DBDriverName string

	// Flag to allow potentially unsafe operations that could lose history
	AllowUnsafe bool

	// Verbosity level
	Verbosity int
}

// Function to return a new HavartiState
func NewHavartiState(workTreeFS fs.FS, cwd *string, workTree *string, dataSourceName string, dbDriverName string) (*HavartiState, error) {
	// FIXME: Stat worktree against the FS that was passed in
	if workTree != nil {
		if _, err := os.Stat(*workTree); errors.Is(err, fs.ErrNotExist) {
			return nil, fmt.Errorf("workTree must be a valid directory: %w", err)
		}
	}

	hvrtState := &HavartiState{
		workTreeFS:      workTreeFS,
		originalWorkDir: cwd,
		workTree:        workTree,
		dataSourceName:  dataSourceName,
		_DBDriverName:   dbDriverName,
	}
	return hvrtState, nil
}

func (hs *HavartiState) GetOriginalWorkDir() (string, error) {
	if hs.originalWorkDir == nil {
		return "", errors.New("originalWorkDir is nil")
	} else {
		return *hs.originalWorkDir, nil
	}
}

func (hs *HavartiState) GetWorkTree() (string, error) {
	if hs.workTree == nil {
		return "", errors.New("worktree is nil")
	} else {
		return *hs.workTree, nil
	}
}

func (hs *HavartiState) ConnectToRepoDB(writable, create bool) (*sql.DB, error) {
	if hs.dataSourceName == "" {
		return nil, MissingDSNError
	} else {
		// TODO: generalize this beyond just sqlite
		parms := CopyOps(SqliteDefaultOpts)
		parms["mode"] = []string{"ro"}
		if writable && create {
			parms["mode"][0] = "rwc"
		} else if writable {
			parms["mode"][0] = "rw"
		}
		dsn := SqliteDSN(hs.dataSourceName, parms)
		if repoDB, err := sql.Open(hs._DBDriverName, dsn); err != nil {
			return nil, err
		} else {
			return repoDB, nil
		}
	}
}

// Set HavartState workTree
func (hs *HavartiState) SetWorkTree(workTree string) {
	hs.workTree = &workTree
}

func init() {
}
