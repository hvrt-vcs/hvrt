package main

import (
	"fmt"
	"log"
	"os"

	"github.com/integrii/flaggy"

	"github.com/eestrada/hvrt"
)

// command line flags
type cmdArgs struct {
	// general flags
	verbosity []bool
	unsafe    bool

	// clone flags
	cloneDir string
}

func parseArgs() cmdArgs {

	parsed_args := cmdArgs{unsafe: false, cloneDir: ""}

	flaggy.BoolSlice(&parsed_args.verbosity, "v", "verbose", "Add increased output. May be specified multiple times to increase verbosity.")
	flaggy.Bool(&parsed_args.unsafe, "", "unsafe", "Force unsafe operations to proceed.")

	// Create the clone subcommand
	cloneSubcommand := flaggy.NewSubcommand("clone")

	// Add flags to the clone subcommand
	cloneSubcommand.String(&parsed_args.cloneDir, "d", "directory", "Directory to clone repo into. Defaults to name of repo in current directory.")

	// Add the subcommand to the parser at position 1
	flaggy.AttachSubcommand(cloneSubcommand, 1)

	flaggy.Parse()

	return parsed_args
}

func main() {
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
