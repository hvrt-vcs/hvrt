package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

var branchSwitchCmd = &cobra.Command{
	Use:     "switch",
	Aliases: []string{"sw", "change", "ch"},
	Short:   "Switch branch for the current worktree",
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("branch switch called")
		return nil
	},
}

func init() {
	branchCmd.AddCommand(branchSwitchCmd)

	branchSwitchCmd.Flags().BoolP("metadata-only", "m", false, "Do not modify any files in the the worktree")
}
