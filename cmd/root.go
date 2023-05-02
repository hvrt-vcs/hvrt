package cmd

import (
	"errors"
	"fmt"
	"math"
	"os"
	"runtime/debug"

	"github.com/hvrt-vcs/hvrt/hvrt"
	"github.com/hvrt-vcs/hvrt/log"
	"github.com/spf13/cobra"
	// "github.com/pelletier/go-toml/v2"
	// "github.com/hvrt-vcs/hvrt/hvrt"
)

type CommandError interface {
	Error() string
	Unwrap() error
	ExitCode() int
}

type commandErrorStruct struct {
	code         int
	wrappedError error
}

func (ce *commandErrorStruct) Error() string {
	if ce.Unwrap() != nil {
		return ce.Unwrap().Error()
	} else {
		return fmt.Sprintf("status code %v", ce.code)
	}
}

func (ce *commandErrorStruct) Unwrap() error {
	return ce.wrappedError
}

func (ce *commandErrorStruct) ExitCode() int {
	return ce.code
}

// Although code is an int, for portability, it should be in the range [0, 125].
func NewCommandError(code int, cause error) CommandError {
	return &commandErrorStruct{code: code, wrappedError: cause}
}

func UnwrapCommandError(err error) CommandError {
	ce, cast_success := err.(CommandError)
	if cast_success {
		return ce
	}

	for ie := errors.Unwrap(err); ie != nil; ie = errors.Unwrap(err) {
		ice, ice_cast_success := err.(CommandError)
		if ice_cast_success {
			return ice
		}
	}

	return nil
}

func WrapPositionalArgsAsCommandError(wrapped_positional_args_func cobra.PositionalArgs) cobra.PositionalArgs {
	return func(cmd *cobra.Command, args []string) error {
		err := wrapped_positional_args_func(cmd, args)
		if err != nil {
			return NewCommandError(ReturnArgumentError, err)
		} else {
			return nil
		}
	}
}

const (
	ReturnSuccess         int = 0
	ReturnGenericError    int = 1
	ReturnArgumentError   int = 2
	ReturnUnexpectedError int = 123
)

const (
	changeDirFlag = "change-directory"
)

// rootCmd represents the base command when called without any subcommands
var rootCmd = &cobra.Command{
	Use:   "hvrt",
	Short: "Havarti VCS",
	Long:  `Havarti is a Hybrid VCS that works both distributed or centralized.`,
	PersistentPreRunE: func(cmd *cobra.Command, args []string) error {
		var err error
		HavartiState, err = hvrt.NewHavartiState(&rootFlags.WorkTree, rootFlags.RepoPath, "sqlite")
		if err != nil {
			return err
		}

		if unsafe, err := cmd.PersistentFlags().GetBool("unsafe"); err != nil {
			return err
		} else {
			HavartiState.AllowUnsafe = unsafe
		}

		if verbosity, err := cmd.PersistentFlags().GetCount("verbose"); err != nil {
			return err
		} else if verbosity > 0 {
			HavartiState.Verbosity = verbosity
		}

		if changeDir, err := cmd.PersistentFlags().GetString(changeDirFlag); err != nil {
			return err
		} else if changeDir != "" {
			cderr := os.Chdir(changeDir)
			if cderr != nil {
				return NewCommandError(ReturnArgumentError, cderr)
			}
		}

		if HavartiState.Verbosity > 0 {
			min := int(math.Max(0, float64(log.DefaultLoggingLevel-(HavartiState.Verbosity*10))))
			log.SetLoggingLevel(min)
		}

		return nil
	},
}

// Execute adds all child commands to the root command and sets flags appropriately.
// This is called by main.main(). It only needs to happen once to the rootCmd.
func Execute() {
	defer func() {
		if r := recover(); r != nil {
			log.Debug.Printf("stacktrace from panic: %s", string(debug.Stack()))
			log.Error.Printf("unexpected error: %s", r)
			os.Exit(ReturnUnexpectedError)
		}
	}()
	if err := rootCmd.Execute(); err != nil {
		log.Error.Println(err)

		if cmdErr := UnwrapCommandError(err); cmdErr != nil {
			os.Exit(cmdErr.ExitCode())
		} else {
			os.Exit(ReturnGenericError)
		}
	} else {
		os.Exit(ReturnSuccess)
	}
}

var HavartiState *hvrt.HavartiState = &hvrt.HavartiState{}

var rootFlags = struct {
	RepoPath string
	WorkTree string
}{
	RepoPath: "./.hvrt/repo.hvrt",
	WorkTree: ".",
}

func init() {
	rootCmd.PersistentFlags().CountP("verbose", "v", "Print more information. Can be specified multiple times to increase verbosity.")
	rootCmd.PersistentFlags().Bool("unsafe", false, "Allow unsafe operations to proceed")
	rootCmd.PersistentFlags().StringVar(
		&rootFlags.RepoPath,
		"repo",
		rootFlags.RepoPath,
		`Path to repo. Unlike git and some other VCS tools, hvrt does not need
the repo data to live inside a main worktree. This allows multiple worktrees to
easily exist in parallel. Multiple worktrees can even point to the same branch
at the same time.`,
	)

	rootCmd.PersistentFlags().StringVar(&rootFlags.WorkTree, "work-tree", rootFlags.WorkTree, "Path to work tree")
	_ = rootCmd.MarkFlagDirname("work-tree")

	rootCmd.PersistentFlags().StringP(
		changeDirFlag, "C",
		"",
		`Run as if started in given path instead of the current working directory.
This option affects options that expect a path name like --repo and
--work-tree because their interpretations of the path names will be made
relative to the working directory specified by the -C option.`,
	)
	_ = rootCmd.MarkFlagDirname(changeDirFlag)

	rootCmd.SetFlagErrorFunc(
		func(c *cobra.Command, err error) error {
			return NewCommandError(ReturnArgumentError, err)
		},
	)
}
