package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

var branchListCmd = &cobra.Command{
	Use:     "list",
	Aliases: []string{"ls"},
	Short:   "List branches",
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("branch ls called")
		return nil
	},
}

func init() {
	branchCmd.AddCommand(branchListCmd)
}
