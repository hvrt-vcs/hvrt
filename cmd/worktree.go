/*
Copyright © 2023 NAME HERE <EMAIL ADDRESS>
*/
package cmd

import (
	"github.com/spf13/cobra"
)

// worktreeCmd represents the worktree command
var worktreeCmd = &cobra.Command{
	Use:     "worktree",
	Short:   "List, create, or delete worktrees",
	Aliases: []string{"wt"},
}

func init() {
	rootCmd.AddCommand(worktreeCmd)
}
