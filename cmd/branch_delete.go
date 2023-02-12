package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

var branchDeleteCmd = &cobra.Command{
	Use:   "delete",
	Short: "Delete branches",
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("branch delete called")
		return nil
	},
	Aliases: []string{"del", "remove", "rm"},
}

func init() {
	branchCmd.AddCommand(branchDeleteCmd)
}
