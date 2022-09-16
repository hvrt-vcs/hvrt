package main

import (
	"fmt"
	"log"

 "github.com/integrii/flaggy"

	"github.com/eestrada/hvrt"
)

func main() {

	// Declare variables and their defaults
	var stringFlag = "defaultValue"

	// Create the subcommand
	subcommand := flaggy.NewSubcommand("subcommandExample")

	// Add a flag to the subcommand
	subcommand.String(&stringFlag, "f", "flag", "A test string flag")

	// Add the subcommand to the parser at position 1
	flaggy.AttachSubcommand(subcommand, 1)

	// Parse the subcommand and all flags
	flaggy.Parse()

	// Use the flag
	fmt.Println(stringFlag)

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
}
