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
)

// Struct definition that contains all state required to run an instance of Havarti
type HavartiState struct {
	// String to the original working directory
	originalWorkDir string

	// The directory in which the worktree is located. May be nil
	workTree *string

	// sql.DB pointer to DB for repository
	RepoDB *sql.DB

	// Driver name for repository DB
	DBDriverName string

	// Flag to allow potentially unsafe operations that could lose history
	AllowUnsafe bool

	// Verbosity level
	Verbosity int
}

// Function to return a new HavartiState
func NewHavartiState(workTree *string, dataSourceName string, dbDriverName string) (*HavartiState, error) {
	var repoDB *sql.DB
	var err error

	cwd, err := os.Getwd()
	if err != nil {
		return nil, err
	}

	if workTree != nil {
		if _, err := os.Stat(*workTree); errors.Is(err, fs.ErrNotExist) {
			return nil, fmt.Errorf("workTree must be a valid directory: %w", err)
		}
	}

	if dataSourceName != "" {
		repoDB, err = sql.Open(dbDriverName, dataSourceName)
		if err != nil {
			return nil, err
		}
	}

	hvrtState := &HavartiState{
		originalWorkDir: cwd,
		workTree:        workTree,
		RepoDB:          repoDB,
		DBDriverName:    dbDriverName,
	}
	return hvrtState, nil
}

func (hs *HavartiState) GetOriginalWorkDir() string {
	return hs.originalWorkDir
}

func (hs *HavartiState) GetWorkTree() (string, error) {
	if hs.workTree == nil {
		return "", errors.New("worktree is nil")
	} else {
		return *hs.workTree, nil
	}
}

// Set HavartState workTree
func (hs *HavartiState) SetWorkTree(workTree string) {
	hs.workTree = &workTree
}

func init() {
}
