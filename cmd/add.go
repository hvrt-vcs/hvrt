package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

// Should we call this `stage` instead of `add`?
var addCmd = &cobra.Command{
	Use:   "add",
	Short: "Add files to the next commit",
	Long: `By default, only previously tracked files are added to commits. By
running the add subcommand, previously untracked files are staged for the next
commit. This command will run recursively when given a directory instead of a
path to an individual file. Rules in .hvrtignore are followed unless '--force'
is supplied.`,
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Println("add called")
	},
}

func init() {
	rootCmd.AddCommand(addCmd)

	// Here you will define your flags and configuration settings.

	// Cobra supports Persistent Flags which will work for this command
	// and all subcommands, e.g.:
	// addCmd.PersistentFlags().String("foo", "", "A help for foo")

	// Cobra supports local flags which will only run when this command
	// is called directly, e.g.:
	// addCmd.Flags().BoolP("toggle", "t", false, "Help message for toggle")
}
