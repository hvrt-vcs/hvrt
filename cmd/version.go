package cmd

import (
	"fmt"
	// "log"

	"github.com/hvrt-vcs/hvrt/hvrt"
	"github.com/spf13/cobra"
)

var versionFlags = struct {
	Bare bool
}{
	Bare: false,
}

func init() {
	rootCmd.AddCommand(versionCmd)

	versionCmd.Flags().BoolVarP(&versionFlags.Bare, "bare", "b", false, "Print out a bare version instead of friendly version")
}

var versionCmd = &cobra.Command{
	Use:   "version",
	Short: "Print the version number of Havarti",
	Long:  `All software has versions. This is Havarti's.`,
	Args:  WrapPositionalArgsAsCommandError(cobra.ExactArgs(0)),
	RunE: func(cmd *cobra.Command, args []string) error {
		var version string
		if versionFlags.Bare {
			version = hvrt.BareVersion
		} else {
			version = hvrt.FormattedVersion
		}
		fmt.Println(version)
		return nil
	},
}
