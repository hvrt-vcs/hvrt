package hvrt

import (
	// "errors"
	// "fmt"
	"io/fs"
	"log"
	// "math/rand"
	"os"
	"path/filepath"
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

func GetWorkTreeRoot(start_dir string) string {

	if start_dir == "" {
		start_dir = "."
	}

	abs_path, err := filepath.Abs(start_dir)
	if err != nil {
		panic("Cannot determine the root of the work tree.")
	}

	cur_dir := abs_path
	for cur_dir != "" {
		cur_dir_fs := os.DirFS(cur_dir)
		entries, _ := fs.ReadDir(cur_dir_fs, ".")
		log.Println(entries)
		log.Println(cur_dir)
		if cur_dir == "/" {
			cur_dir = ""
		} else {
			cur_dir = filepath.Dir(cur_dir)
		}
	}

	return ""
}

type RepoStat struct {
	DelPaths []string
	ModPaths []string
	NewPaths []string
	UnkPaths []string
}

func Status(repo_file, work_tree string) (RepoStat, error) {
	real_work_tree := GetWorkTreeRoot(work_tree)
	log.Println(real_work_tree)


	stat := RepoStat{}
	fileSystem := os.DirFS(work_tree)
	log.Println(
		"values of variables at status call:",
		repo_file,
		work_tree,
		fileSystem,
	)
	panic("whatever")

	fs.WalkDir(fileSystem, ".", func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			log.Fatal(err)
		}
		stat.ModPaths = append(stat.ModPaths, path)
		return nil
	})
	return stat, nil
}
