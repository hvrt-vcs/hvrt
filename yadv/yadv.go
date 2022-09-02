package yadv

import "fmt"

// Hello returns a greeting for the named person.
func Hello(name string) string {
	// Return a greeting the embeds the name in a message.
	message := fmt.Sprintf("Hi, %v. Welcome!", name)
	return message
}

