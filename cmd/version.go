package cmd

import (
	"fmt"
	// "log"

	"github.com/eestrada/hvrt/hvrt"
	"github.com/spf13/cobra"
)

var versionFlags = struct {
	SemanticVersion bool
}{
	SemanticVersion: false,
}

func init() {
	versionCmd.Flags().BoolVarP(&versionFlags.SemanticVersion, "semantic-version", "s", false, "Print out a semantic version instead of friendly version")

	rootCmd.AddCommand(versionCmd)
}

var versionCmd = &cobra.Command{
	Use:   "version",
	Short: "Print the version number of Havarti",
	Long:  `All software has versions. This is Havarti's.`,
	Run: func(cmd *cobra.Command, args []string) {
		var version string
		if versionFlags.SemanticVersion {
			version = hvrt.SemanticVersion
		} else {
			version = hvrt.FormattedVersion
		}
		fmt.Println(version)
	},
}
