package hvrt

import (
	// "errors"
	// "fmt"
	"io/fs"
	"log"
	// "math/rand"
	"os"
	// "time"
	// "modernc.org/sqlite"
)

// init sets initial values for variables used in the package.
func init() {
}

func Status(repo_file, work_tree *string, paths_chan chan string) error {
	fileSystem := os.DirFS(*work_tree)
	log.Println(
		"values of variables at status call:",
		*repo_file,
		*work_tree,
		fileSystem,
		paths_chan,
	)

	fs.WalkDir(fileSystem, ".", func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			log.Fatal(err)
		}
		paths_chan <- path
		return nil
	})
	close(paths_chan)
	return nil
}
