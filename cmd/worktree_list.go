package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

var worktreeListCmd = &cobra.Command{
	Use:     "list",
	Short:   "List all registered worktrees for repo with their location on disk",
	Aliases: []string{"ls"},
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("worktree list called")
		return nil
	},
}

func init() {
	worktreeCmd.AddCommand(worktreeListCmd)
}
