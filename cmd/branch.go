package cmd

import (
	"github.com/spf13/cobra"
)

var branchCmd = &cobra.Command{
	Use:   "branch",
	Short: "List, create, switch, or delete branches",
}

func init() {
	rootCmd.AddCommand(branchCmd)
}
