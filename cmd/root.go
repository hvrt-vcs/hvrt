package cmd

import (
	"log"
	"os"

	"github.com/spf13/cobra"
	// "github.com/pelletier/go-toml/v2"
	// "github.com/hvrt-vcs/hvrt/hvrt"
)

const (
	ReturnSuccess         = 0
	ReturnGenericError    = 1
	ReturnArgumentError   = 2
	ReturnUnexpectedError = 123
)

// rootCmd represents the base command when called without any subcommands
var rootCmd = &cobra.Command{
	Use:   "hvrt",
	Short: "Havarti VCS",
	Long:  `Havarti is a Hybrid VCS that works both distributed or centralized.`,
	// Uncomment the following line if your bare application
	// has an action associated with it:
	// Run: func(cmd *cobra.Command, args []string) { },
	PersistentPreRunE: func(cmd *cobra.Command, args []string) error {
		if rootFlags.ChangeDir != "" {
			cderr := os.Chdir(rootFlags.ChangeDir)
			if cderr != nil {
				returnCode = ReturnArgumentError
				return cderr
			}
		}
		return nil
	},
}

// Execute adds all child commands to the root command and sets flags appropriately.
// This is called by main.main(). It only needs to happen once to the rootCmd.
func Execute() {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("Encountered unexpected error: %s", r)
			os.Exit(ReturnUnexpectedError)
		}
	}()
	err := rootCmd.Execute()
	if err != nil {
		if returnCode != 0 {
			os.Exit(returnCode)
		} else {
			os.Exit(ReturnGenericError)
		}
	} else {
		os.Exit(ReturnSuccess)
	}
}

var returnCode int

var rootFlags = struct {
	RepoPath  string
	WorkTree  string
	ChangeDir string
	Unsafe    bool
}{
	RepoPath:  "./.hvrt/repo.hvrt",
	WorkTree:  ".",
	ChangeDir: "",
	Unsafe:    false,
}

func init() {
	// Assume success
	returnCode = ReturnSuccess

	// Here you will define your flags and configuration settings.
	// Cobra supports persistent flags, which, if defined here,
	// will be global for your application.

	rootCmd.PersistentFlags().BoolVar(&rootFlags.Unsafe, "unsafe", rootFlags.Unsafe, "Allow unsafe operations to proceed")
	rootCmd.PersistentFlags().StringVar(
		&rootFlags.RepoPath,
		"repo",
		rootFlags.RepoPath,
		`Path to repo. Unlike git and some other VCS tools, hvrt does not need
the repo data to live inside a main worktree. This allows multiple worktrees to
easily exist in parallel.`,
	)
	rootCmd.PersistentFlags().StringVar(&rootFlags.WorkTree, "work-tree", rootFlags.WorkTree, "Path to work tree")
	rootCmd.PersistentFlags().StringVarP(
		&rootFlags.ChangeDir,
		"change-directory", "C",
		rootFlags.ChangeDir,
		`Run as if started in given path instead of the current working directory.
This option affects options that expect a path name like --repo and
--work-tree because their interpretations of the path names will be made
relative to the working directory specified by the -C option.`,
	)

	// Cobra also supports local flags, which will only run
	// when this action is called directly.
	// rootCmd.Flags().BoolP("toggle", "t", false, "Help message for toggle")
}
