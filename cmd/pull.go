package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

var pullCmd = &cobra.Command{
	Use:   "pull",
	Short: "pull changes from a remote",
	Long:  `In autosync mode, this is run immediately before commit.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("pull called")
		return nil
	},
}

func init() {
	rootCmd.AddCommand(pullCmd)
}
