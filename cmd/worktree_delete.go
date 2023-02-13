package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

var worktreeDeleteCmd = &cobra.Command{
	Use:     "delete",
	Short:   "Delete worktree",
	Aliases: []string{"del", "remove", "rm", "disconnect"},
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("worktree delete called")
		return nil
	},
}

func init() {
	worktreeCmd.AddCommand(worktreeDeleteCmd)
}
