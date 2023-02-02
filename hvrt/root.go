package hvrt

import (
	"io"
	"log"
	"os"
	"strconv"
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
	log_debug   *log.Logger
	log_info    *log.Logger
	log_warning *log.Logger
	log_error   *log.Logger
)

// init sets initial values for variables used in the package.
func init() {
	if val, present := os.LookupEnv("HVRT_VERBOSITY"); present && val != "" {
		verbosity_level, err := strconv.Atoi(val)
		if err != nil {
			SetLoggingLevel(verbosity_level)
			return
		}
	}
	SetLoggingLevel(5)
}

// TODO: split logging code into separate package so that all packages under
// hvrt can take advantage of it.
func SetLoggingLevel(level int) {
	error_writer, warning_writer, info_writer, debug_writer := io.Discard, io.Discard, io.Discard, io.Discard
	if level >= 1 {
		error_writer = os.Stderr
	}
	if level >= 2 {
		warning_writer = os.Stderr
	}
	if level >= 3 {
		info_writer = os.Stderr
	}
	if level >= 4 {
		debug_writer = os.Stderr
	}

	logFlags := log.LstdFlags
	log_error = log.New(error_writer, "ERROR: ", logFlags)
	log_warning = log.New(warning_writer, "WARNING: ", logFlags)
	log_info = log.New(info_writer, "INFO: ", logFlags)
	log_debug = log.New(debug_writer, "DEBUG: ", logFlags)
}
