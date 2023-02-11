package cmd

import (
	"github.com/spf13/cobra"
)

var rmCmd = &cobra.Command{
	Use:   "rm",
	Short: "Remove a file from being tracked in the repo",
	Long: `After removing a file from the repo, it will not automatically get picked 
up again in future commits until and if it is added again via the add subcommand.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
	Args: WrapPositionalArgsAsCommandError(cobra.MinimumNArgs(1)),
}

func init() {
	rootCmd.AddCommand(rmCmd)

	rmCmd.Flags().BoolP("recursive", "r", false, "Allow recursive removal when a directory name is given.")
	rmCmd.Flags().BoolP("staged", "s", false, "Only remove a file from the staging area.")
	rmCmd.Flags().BoolP("keep", "k", false, "Only remove a file from the repo, not from on disk.")
}
