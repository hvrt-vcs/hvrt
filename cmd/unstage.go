package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

var unstageCmd = &cobra.Command{
	Use:   "unstage",
	Short: "Remove a change from the stage",
	Long: `The change will remain in the work directory tree. This behaves
identically to 'hvrt rm --staged --keep'.`,
	Args: WrapPositionalArgsAsCommandError(cobra.MinimumNArgs(1)),
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("unstage called")
		return nil
	},
}

func init() {
	rootCmd.AddCommand(unstageCmd)

	unstageCmd.Flags().BoolP("recursive", "r", false, "Allow recursive removal when a directory name is given.")
}
