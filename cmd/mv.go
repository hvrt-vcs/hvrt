package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

var mvCmd = &cobra.Command{
	Use:   "mv",
	Short: "Move/rename a file, directory, or symlink",
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("mv called")
		return nil
	},
	Args: WrapPositionalArgsAsCommandError(cobra.ExactArgs(2)),
}

func init() {
	rootCmd.AddCommand(mvCmd)

	mvCmd.Flags().Bool("stage-only", false, "Do not move the file(s) ondisk, but do record it as such in the staging area. Useful to record renames after they have already happened ondisk.")
	mvCmd.Flags().Bool("cat", false, "Concatenate file instead of overwriting. More importantly this affects how blame and history determine where lines come from.")
}
