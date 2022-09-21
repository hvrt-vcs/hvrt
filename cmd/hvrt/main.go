package main

import (
	// "fmt"
	"log"
	"os"

	"github.com/integrii/flaggy"
	"github.com/pelletier/go-toml/v2"

	"github.com/eestrada/hvrt"
)

// config values
type CfgValues struct {
	Autosync bool
	Version  int
	Name     string
	Tags     []string
}

// command line flags
type CmdArgs struct {
	// general flags
	Verbosity []bool
	Unsafe    bool
	RepoFile    string
	WorkTree string

	// status flags
	Untracked bool
}

func parseArgs() CmdArgs {
	parsed_args := CmdArgs{Unsafe: false, RepoFile: ".hvrt/repo.sqlite", WorkTree: "."}

	flaggy.BoolSlice(&parsed_args.Verbosity, "v", "verbose", "Add increased output. May be specified multiple times to increase verbosity.")
	flaggy.Bool(&parsed_args.Unsafe, "", "unsafe", "Force unsafe operations to proceed.")

	flaggy.String(&parsed_args.RepoFile, "r", "repo-file", "Location of the repo Sqlite file.")
	flaggy.String(&parsed_args.WorkTree, "w", "work-tree", "Location of a given work tree.")

	// Create the init subcommand
	initSubcommand := flaggy.NewSubcommand("init")

	// Add the subcommand to the parser at position 1
	flaggy.AttachSubcommand(initSubcommand, 1)

	// Create the status subcommand
	statusSubcommand := flaggy.NewSubcommand("status")

	// Add flags to the status subcommand
	statusSubcommand.Bool(&parsed_args.Untracked, "u", "untracked", "Show untracked files as well.")

	// Add the subcommand to the parser at position 1
	flaggy.AttachSubcommand(statusSubcommand, 1)

	flaggy.Parse()

	return parsed_args
}

func realMain() int {
	defaultCfg := `
autosync = true
version = 2
name = "go-toml"
tags = ["go", "toml"]
`

	var cfg CfgValues
	err := toml.Unmarshal([]byte(defaultCfg), &cfg)
	if err != nil {
		panic(err)
	}
	log.Printf("Parsed configs: %+v\n", cfg)

	parsed_args := parseArgs()

	log.Printf("Parsed args: %+v\n", parsed_args)

	// // Set properties of the predefined Logger, including
	// // the log entry prefix and a flag to disable printing
	// // the time, source file, and line number.
	// log.SetPrefix("greetings: ")
	// log.SetFlags(0)
	//
	// // A slice of names.
	// names := []string{"Gladys", "Samantha", "Darrin"}
	//
	// // Request greeting messages for the names.
	// messages, err := hvrt.Hellos(names)
	// if err != nil {
	// 	log.Fatal(err)
	// }
	// // If no error was returned, print the returned map of
	// // messages to the console.
	// fmt.Println(messages)

	return hvrt.Status(parsed_args.RepoFile, parsed_args.WorkTree)
}

func main() {
	os.Exit(realMain())
}
