package cmd

import (
	"github.com/hvrt-vcs/hvrt/hvrt"
	"github.com/spf13/cobra"
)

// Should we call this `stage` instead of `add`?
var addCmd = &cobra.Command{
	Use:   "add",
	Short: "Add files to the next commit",
	Long: `By default, only previously tracked files are automatically added to commits. By
running the add subcommand, previously untracked files are staged for the next
commit. This command will run recursively when given a directory instead of a
path to an individual file. Rules in .hvrtignore are followed unless '--force'
is supplied.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return hvrt.AddFiles(rootFlags.WorkTree, args)
	},
	Args: WrapPositionalArgsAsCommandError(cobra.MinimumNArgs(1)),
}

func init() {
	rootCmd.AddCommand(addCmd)

	addCmd.Flags().BoolP("force", "f", false, "Forcefully add a file, even if it would normally be ignored")
	addCmd.Flags().BoolP("interactive", "i", false, "Interactively choose the parts of the given file(s) to add to the staging area")
}
