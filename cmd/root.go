package cmd

import (
	"log"
	"os"

	"github.com/spf13/cobra"
	// "github.com/pelletier/go-toml/v2"
	// "github.com/eestrada/hvrt/hvrt"
)

// rootCmd represents the base command when called without any subcommands
var rootCmd = &cobra.Command{
	Use:   "hvrt",
	Short: "Havarti VCS",
	Long:  `Havarti is a Hybrid VCS that works both distributed or centralized.`,
	// Uncomment the following line if your bare application
	// has an action associated with it:
	// Run: func(cmd *cobra.Command, args []string) { },
}

// Execute adds all child commands to the root command and sets flags appropriately.
// This is called by main.main(). It only needs to happen once to the rootCmd.
func Execute() {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("Encountered unexpected error: %s", r)
			os.Exit(123)
		}
	}()
	err := rootCmd.Execute()
	if err != nil {
		log.Printf("Encountered error: %s", err)
		os.Exit(1)
	} else {
		os.Exit(0)
	}
}

var RepoPath string
var WorkTree string

func init() {
	// Here you will define your flags and configuration settings.
	// Cobra supports persistent flags, which, if defined here,
	// will be global for your application.
	RepoPath = "./.hvrt/repo.hvrt"
	WorkTree = "."

	rootCmd.PersistentFlags().StringVar(&RepoPath, "repo", RepoPath, "Path to repo (default is ./.hvrt/repo.hvrt)")
	rootCmd.PersistentFlags().StringVar(&WorkTree, "work-tree", WorkTree, "Path to work tree (default is .)")

	// Cobra also supports local flags, which will only run
	// when this action is called directly.
	// rootCmd.Flags().BoolP("toggle", "t", false, "Help message for toggle")
}
