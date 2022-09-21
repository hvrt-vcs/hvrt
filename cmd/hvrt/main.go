package main

import (
	"fmt"
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

	// init flags
	RepoFile    string
	CheckoutDir string
}

func parseArgs() CmdArgs {
	parsed_args := CmdArgs{Unsafe: false}

	flaggy.BoolSlice(&parsed_args.Verbosity, "v", "verbose", "Add increased output. May be specified multiple times to increase verbosity.")
	flaggy.Bool(&parsed_args.Unsafe, "", "unsafe", "Force unsafe operations to proceed.")

	// Create the init subcommand
	initSubcommand := flaggy.NewSubcommand("init")

	// Add flags to the clone subcommand
	initSubcommand.String(&parsed_args.RepoFile, "r", "repo-file", "Where to create the repo Sqlite file.")
	initSubcommand.String(&parsed_args.RepoFile, "c", "checkout", "Where to initially checkout the default branch.")

	// Add the subcommand to the parser at position 1
	flaggy.AttachSubcommand(initSubcommand, 1)

	flaggy.Parse()

	return parsed_args
}

func main() {

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
	fmt.Println("autosync:", cfg.Autosync)
	fmt.Println("version:", cfg.Version)
	fmt.Println("name:", cfg.Name)
	fmt.Println("tags:", cfg.Tags)

	parsed_args := parseArgs()

	log.Printf("%+v\n", parsed_args)

	// Set properties of the predefined Logger, including
	// the log entry prefix and a flag to disable printing
	// the time, source file, and line number.
	log.SetPrefix("greetings: ")
	log.SetFlags(0)

	// A slice of names.
	names := []string{"Gladys", "Samantha", "Darrin"}

	// Request greeting messages for the names.
	messages, err := hvrt.Hellos(names)
	if err != nil {
		log.Fatal(err)
	}
	// If no error was returned, print the returned map of
	// messages to the console.
	fmt.Println(messages)
	os.Exit(0)
}
