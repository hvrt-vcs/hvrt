package log

import (
	"io"
	"log"
	"os"
	"strconv"
)

const (
	DefaultLoggingLevel = 40
)

var (
	LoggingLevel int         = DefaultLoggingLevel
	LogFlags     int         = log.LstdFlags
	Debug        *log.Logger = log.New(io.Discard, "DEBUG: ", log.LstdFlags)
	Info         *log.Logger = log.New(io.Discard, "INFO: ", log.LstdFlags)
	Warning      *log.Logger = log.New(io.Discard, "WARNING: ", log.LstdFlags)
	Error        *log.Logger = log.New(io.Discard, "ERROR: ", log.LstdFlags)

	// Where logs get written to can be overridden. After setting this value, SetLoggingLevel must be called.
	LogWriter io.Writer = os.Stderr
)

// init sets initial values for variables used in the package.
func init() {
	if val, present := os.LookupEnv("HVRT_VERBOSITY"); present && val != "" {
		verbosity_level, err := strconv.Atoi(val)
		if err != nil {
			SetLoggingLevel(50 - (verbosity_level * 10))
			return
		}
	}
	SetLoggingLevel(LoggingLevel)
}

func SetLoggingLevel(level int) {
	error_writer, warning_writer, info_writer, debug_writer := io.Discard, io.Discard, io.Discard, io.Discard

	if level < 0 {
		if LoggingLevel < 0 {
			level = DefaultLoggingLevel
		} else {
			level = LoggingLevel
		}
	}

	// having a nil writer would cause errors.
	if LogWriter == nil {
		LogWriter = os.Stderr
	}

	if level <= 10 {
		debug_writer = LogWriter
	}
	if level <= 20 {
		info_writer = LogWriter
	}
	if level <= 30 {
		warning_writer = LogWriter
	}
	if level <= 40 {
		error_writer = LogWriter
	}

	Debug = log.New(debug_writer, "DEBUG: ", LogFlags)
	Info = log.New(info_writer, "INFO: ", LogFlags)
	Warning = log.New(warning_writer, "WARNING: ", LogFlags)
	Error = log.New(error_writer, "ERROR: ", LogFlags)
}
