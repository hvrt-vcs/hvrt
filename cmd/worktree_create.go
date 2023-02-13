package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

var worktreeCreateCmd = &cobra.Command{
	Use:     "create",
	Short:   "Create worktree",
	Aliases: []string{"cr", "new"},
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("worktree create called")
		return nil
	},
}

func init() {
	worktreeCmd.AddCommand(worktreeCreateCmd)

	worktreeCreateCmd.Flags().StringP("name", "n", "", "Give an explicit name to registered worktree. Otherwise is registered only with its location on disk.")
	worktreeCreateCmd.Flags().BoolP(
		"unregistered",
		"u",
		false,
		`Do not register created worktree with repo. Worktrees can be orphan worktrees.
That is to say, they do not report to the repo that they are associated with it. However, they can still interact with
the repo like any other worktree. One example of where this can be useful is for ephemeral worktrees (for example in
CI/CD workflows) that may potentially not get properly cleaned up, leaving open the possibility of cluttering the repo
with information about dead, degenerate, or missing worktrees.`)

	// unregistered worktrees cannot have names
	worktreeCreateCmd.MarkFlagsMutuallyExclusive("name", "unregistered")
}
