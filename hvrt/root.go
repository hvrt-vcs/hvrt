package hvrt

import (
	"errors"
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

func init() {
}
