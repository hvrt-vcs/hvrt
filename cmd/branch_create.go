package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

var branchCreateFlags = struct {
	Switch    bool
	LocalOnly bool
}{
	Switch:    true,
	LocalOnly: false,
}

var branchCreateCmd = &cobra.Command{
	Use:     "create",
	Aliases: []string{"cr", "new"},
	Short:   "Create branches",
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("branch create called")
		return nil
	},
}

func init() {
	branchCmd.AddCommand(branchCreateCmd)

	branchCreateCmd.Flags().BoolVarP(&branchCreateFlags.Switch, "switch", "s", false, "Switch worktree to new branch immediately after creation")
	branchCreateCmd.Flags().BoolVarP(&branchCreateFlags.Switch, "local-only", "l", false, "Do not autosync this branch upstream. Can be changed later.")
}
