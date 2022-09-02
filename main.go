package main

import "fmt"

// import "rsc.io/quote"

import "github.com/eestrada/yadv"

func main() {
	message := yadv.Hello("Some random name")
	fmt.Println(message)
}

