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

// func IgnoreFileParse(ignore_file io.Reader) []string {
// 	patterns := make([]string, 0, 8)
// 	for line := range ignore_file {
// 		switch line {
// 		case condition:
//
// 		}
// 	}
// }

type RepoStat struct {
	DelPaths []string
	ModPaths []string
	NewPaths []string
	UnkPaths []string
}

func Status(repo_file, work_tree string) (RepoStat, error) {
	stat := RepoStat{}
	fileSystem := os.DirFS(work_tree)
	log.Println(
		"values of variables at status call:",
		repo_file,
		work_tree,
		fileSystem,
	)

	fs.WalkDir(fileSystem, ".", func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			log.Fatal(err)
		}
		stat.ModPaths = append(stat.ModPaths, path)
		return nil
	})
	return stat, nil
}
