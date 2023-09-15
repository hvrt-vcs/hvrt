package hvrt

import (
	"database/sql"
	"errors"
	"fmt"
	"io/fs"
	"net/url"
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
	dsn_url *url.URL

	// Driver name for repository DB
	_DBDriverName string

	// Flag to allow potentially unsafe operations that could lose history
	AllowUnsafe bool

	// Verbosity level
	Verbosity int
}

// Function to return a new HavartiState
func NewHavartiState(workTreeFS fs.FS, cwd *string, workTree *string, dataSourceName string, dbDriverName string) (*HavartiState, error) {
	var err error
	// FIXME: Stat worktree against the FS that was passed in
	if workTreeFS != nil && workTree != nil {
		if _, err = fs.Stat(workTreeFS, *workTree); errors.Is(err, fs.ErrNotExist) {
			return nil, fmt.Errorf("workTree must be a valid directory: %w", err)
		}
	}

	var dsn_url *url.URL = nil
	if dataSourceName != "" {
		if dsn_url, err = url.Parse(dataSourceName); err != nil {
			return nil, err
		}
	}

	// It is currently not an error for both workTree and dsn_url to be nil.
	hvrtState := &HavartiState{
		workTreeFS:      workTreeFS,
		originalWorkDir: cwd,
		workTree:        workTree,
		dsn_url:         dsn_url,
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

func (hs *HavartiState) GetDSN() (*url.URL, error) {
	if hs.dsn_url == nil {
		return nil, MissingDSNError
	} else {
		return hs.dsn_url, nil
	}
}

func (hs *HavartiState) ConnectToRepoDB(writable, create bool) (*sql.DB, error) {
	if dsn_url, err := hs.GetDSN(); err != nil {
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

		dsn, err := AddParmsToDSN(dsn_url, parms)
		if err != nil {
			return nil, err
		}

		repoDB, err := sql.Open(hs._DBDriverName, dsn.String())
		if err != nil {
			return nil, err
		}

		// TODO: set sqlite pragmas here, such as enforcing foreign constraints, etc.
		return repoDB, nil
	}
}

// Set HavartState workTree
func (hs *HavartiState) SetWorkTree(workTree string) {
	hs.workTree = &workTree
}

// Set HavartState to allow potentially unsafe operations during the duration of
// the thunk. When the thunk returns, the state will be restored to its previous
// value. If the value is changed during the duration of the thunk, that value
// will be overwritten by the restored previous value. Any error returned by the
// thunk is returned by this method.
func (hs *HavartiState) AllowUnsafeTemporarily(thnk ThunkErr) error {
	prevUnsafeVal := hs.AllowUnsafe
	hs.AllowUnsafe = true
	defer func() { hs.AllowUnsafe = prevUnsafeVal }()
	return thnk()
}

func init() {
}
