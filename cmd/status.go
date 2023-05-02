package cmd

import (
	"fmt"

	"github.com/hvrt-vcs/hvrt/hvrt"
	"github.com/hvrt-vcs/hvrt/log"
	"github.com/spf13/cobra"
)

func init() {
	rootCmd.AddCommand(statusCmd)
}

var statusCmd = &cobra.Command{
	Use:   "status",
	Short: "Print the status of the given repository and work tree",
	RunE: func(cmd *cobra.Command, args []string) error {
		stat, err := HavartiState.Status()
		if err != nil {
			return err
		} else if stat == nil {
			return fmt.Errorf("received nil stat value")
		}

		for _, mod_path := range stat.ModPaths {
			fhp, err := hvrt.HashFile(mod_path)
			if err != nil {
				log.Error.Println(err)
			} else {
				fmt.Println(fhp)
			}
		}

		return nil
	},
}
