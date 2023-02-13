package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

var cpCmd = &cobra.Command{
	Use:     "cp",
	Aliases: []string{"copy"},
	Short:   "Copy/duplicate a file, directory, or symlink",
	Args:    WrapPositionalArgsAsCommandError(cobra.MinimumNArgs(2)),
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("cp called")
		return nil
	},
}

func init() {
	rootCmd.AddCommand(cpCmd)

	cpCmd.Flags().Bool("stage-only", false, "Do not move the file(s) ondisk, but do record it as such in the staging area. Useful to record renames after they have already happened ondisk.")
	cpCmd.Flags().Bool("cat", false, "Concatenate file instead of overwriting. More importantly this affects how blame and history determine where lines come from.")
}
