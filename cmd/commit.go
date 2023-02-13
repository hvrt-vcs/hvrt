package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

var commitCmd = &cobra.Command{
	Use:   "commit",
	Short: "commit changes to the repo",
	Long:  `Previously tracked files will be automatically added to the commit. Use the '--staged-only' flag to behave otherwise.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("commit called")
		return nil
	},
}

func init() {
	rootCmd.AddCommand(commitCmd)

	commitCmd.Flags().BoolP("staged-only", "s", false, "Commit only changes that have previously been placed in the staging area.")
	commitCmd.Flags().StringP("message", "m", "", "Commit message.")
	commitCmd.Flags().String("author", "", "Commit author.")
	commitCmd.Flags().String("committer", "", "Individual creating the commit. Defaults to author if not provided.")
	commitCmd.Flags().BoolP("sign", "S", false, "Sign commit.")
}
