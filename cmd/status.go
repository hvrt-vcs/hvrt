package cmd

import (
	"fmt"
	"log"

	"github.com/hvrt-vcs/hvrt/hvrt"
	"github.com/spf13/cobra"
)

func init() {
	// Here you will define your flags and configuration settings.
	// Cobra supports persistent flags, which, if defined here,
	// will be global for your application.

	// rootCmd.PersistentFlags().StringVar(&cfgFile, "config", "", "config file (default is $HOME/.hvrt.yaml)")

	// Cobra also supports local flags, which will only run
	// when this action is called directly.
	// statusCmd.Flags().BoolP("toggle", "t", false, "Help message for toggle")

	rootCmd.AddCommand(statusCmd)
}

var statusCmd = &cobra.Command{
	Use:   "status",
	Short: "Print the status of the given repository and work tree",
	RunE: func(cmd *cobra.Command, args []string) error {
		fhpchan := make(chan hvrt.FileHashPair)
		stat, err := hvrt.Status(rootFlags.RepoPath, rootFlags.WorkTree)
		if err != nil {
			return err
		} else if stat == nil {
			return fmt.Errorf("received nil stat value")
		}

		for _, mod_path := range stat.ModPaths {
			go func(mod_path string) {
				fhp, err := hvrt.HashFile(mod_path)
				if err != nil {
					log.Println("Encountered error:", err)
					return
				}
				fhpchan <- fhp
			}(mod_path)
		}
		for range stat.ModPaths {
			pair := <-fhpchan
			fmt.Println("pair from channel:", pair)
		}
		return nil
	},
}
