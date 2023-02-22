package cmd

import (
	"github.com/hvrt-vcs/hvrt/hvrt"
	"github.com/spf13/cobra"
)

var commitFlags struct {
	staged_only bool
	message     string
	author      string
	committer   string
	sign        bool
}

var commitCmd = &cobra.Command{
	Use:   "commit",
	Short: "commit changes to the repo",
	Long:  `Previously tracked files will be automatically added to the commit. Use the '--staged-only' flag to behave otherwise.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return hvrt.Commit(rootFlags.WorkTree, commitFlags.message, commitFlags.author, commitFlags.committer)
	},
}

func init() {
	rootCmd.AddCommand(commitCmd)

	commitCmd.Flags().BoolVarP(&commitFlags.staged_only, "staged-only", "s", false, "Commit only changes that have previously been placed in the staging area.")

	// FIXME: pull message from user interactively when not given on command line
	commitCmd.Flags().StringVarP(&commitFlags.message, "message", "m", "", "Commit message.")
	_ = commitCmd.MarkFlagRequired("message")

	// FIXME: alert user when value not set in config or given on command line.
	// Supply with a simple default value based on username@hostname for the
	// current system.
	commitCmd.Flags().StringVar(&commitFlags.author, "author", "", "Commit author.")
	_ = commitCmd.MarkFlagRequired("author")

	commitCmd.Flags().StringVar(&commitFlags.committer, "committer", "", "Individual creating the commit. Defaults to author if not provided.")

	// TODO: implement commit signing
	// commitCmd.Flags().BoolVarP(&commitFlags.sign, "sign", "S", false, "Sign commit.")

}
