/*
Copyright © 2023 NAME HERE <EMAIL ADDRESS>
*/
package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

var logCmd = &cobra.Command{
	Use:   "log",
	Short: "Show commit logs",
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("log called")
		return nil
	},
}

func init() {
	rootCmd.AddCommand(logCmd)
}
