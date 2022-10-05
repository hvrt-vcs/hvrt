package cmd

import (
	"fmt"
	// "log"

	"github.com/eestrada/hvrt/hvrt"
	"github.com/spf13/cobra"
)

func init() {
	rootCmd.AddCommand(versionCmd)
}

var versionCmd = &cobra.Command{
	Use:   "version",
	Short: "Print the version number of Havarti",
	Long:  `All software has versions. This is Havarti's.`,
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Println(hvrt.FormattedVersion)
	},
}
