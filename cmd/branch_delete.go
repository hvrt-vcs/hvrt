package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

var branchDeleteCmd = &cobra.Command{
	Use:     "delete",
	Aliases: []string{"del", "remove", "rm"},
	Short:   "Delete branches",
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("branch delete called")
		return nil
	},
}

func init() {
	branchCmd.AddCommand(branchDeleteCmd)
}
