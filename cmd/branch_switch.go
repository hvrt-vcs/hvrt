package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

var branchSwitchCmd = &cobra.Command{
	Use:   "switch",
	Short: "Switch branches",
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("branch switch called")
		return nil
	},
	Aliases: []string{"change", "cd"},
}

func init() {
	branchCmd.AddCommand(branchSwitchCmd)
}
