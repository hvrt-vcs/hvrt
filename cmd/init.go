package cmd

import (
	// "fmt"

	"github.com/eestrada/hvrt/hvrt"
	"github.com/spf13/cobra"
)

var initFlags = struct {
	Bare bool
}{
	Bare: false,
}

// initCmd represents the init command
var initCmd = &cobra.Command{
	Use:   "init",
	Short: "Initialize a new repository",
	Long: `The new repo can specify the repository path and/or working tree using the global flags.

	If neither are specified, this defaults to using the current directory as the
	working tree and initializing the repository internally to it (like git).`,

	RunE: func(cmd *cobra.Command, args []string) error {
		err := hvrt.InitLocalAll(rootFlags.RepoPath, rootFlags.WorkTree)
		if err != nil {
			return err
		} else {
			return nil
		}
	},
}

func init() {
	rootCmd.AddCommand(initCmd)

	// Here you will define your flags and configuration settings.

	// Cobra supports Persistent Flags which will work for this command
	// and all subcommands, e.g.:
	// initCmd.PersistentFlags().String("foo", "", "A help for foo")

	// Cobra supports local flags which will only run when this command
	// is called directly, e.g.:
	initCmd.Flags().BoolVarP(&initFlags.Bare, "bare", "b", false, "Do not initialize a work tree")
}
