package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

var branchCreateCmd = &cobra.Command{
	Use:   "create",
	Short: "Create branches",
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("branch create called")
		return nil
	},
	Aliases: []string{"new"},
}

func init() {
	branchCmd.AddCommand(branchCreateCmd)
}
