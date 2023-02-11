package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

var pushCmd = &cobra.Command{
	Use:   "push",
	Short: "push repo changes to a remote",
	Long:  `In autosync mode, this is run immediately after commit.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("push called")
		return nil
	},
}

func init() {
	rootCmd.AddCommand(pushCmd)
}
