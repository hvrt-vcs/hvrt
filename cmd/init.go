package cmd

import (
	"github.com/hvrt-vcs/hvrt/hvrt"
	"github.com/spf13/cobra"
)

var initFlags = struct {
	Bare          bool
	DefaultBranch string
}{
	Bare:          false,
	DefaultBranch: "trunk",
}

var initCmd = &cobra.Command{
	Use:   "init",
	Short: "Initialize a new repository/worktree",
	Long: `The new repo can specify the repository path and/or working tree using the global flags.

	If neither are specified, this defaults to using the current directory as the
	working tree and initializing the repository internally to it (like git).`,

	RunE: func(cmd *cobra.Command, args []string) error {
		return hvrt.InitLocalAll(rootFlags.RepoPath, rootFlags.WorkTree, initFlags.DefaultBranch)
	},
}

func init() {
	rootCmd.AddCommand(initCmd)

	// init command never takes positional args
	initCmd.Args = WrapPositionalArgsAsCommandError(cobra.NoArgs)

	// take positional arguments specify directory to initialize
	// initCmd.Args = WrapPositionalArgsAsCommandError(cobra.MaximumNArgs(1))

	initCmd.Flags().BoolVarP(&initFlags.Bare, "bare", "b", false, "Do not initialize a work tree")
	initCmd.Flags().StringVarP(&initFlags.DefaultBranch, "default-branch", "d", initFlags.DefaultBranch, "default branch to use when initializing repo")
}
