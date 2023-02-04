package hvrt

import (
	"encoding/hex"
	"errors"
	"io"
	"io/fs"
	"os"
	"path/filepath"

	"github.com/hvrt-vcs/hvrt/file_ignore"
	"github.com/hvrt-vcs/hvrt/log"

	"golang.org/x/crypto/sha3"
	// "modernc.org/sqlite"
)

// init sets initial values for variables used in the package.
func init() {
}

type FileHashPair struct {
	HashAlgo  string
	HexDigest string
	FilePath  string
}

func HashFile(file_path string) (FileHashPair, error) {
	source_file, err := os.Open(file_path)
	if err != nil {
		return FileHashPair{}, errors.New("could not open source file")
	}
	defer source_file.Close()

	hash := sha3.New256()
	_, err = io.Copy(hash, source_file)
	if err != nil {
		return FileHashPair{}, err
	}

	digest := hash.Sum([]byte{})
	hex_digest := hex.EncodeToString(digest)
	return FileHashPair{HashAlgo: "sha3-256", HexDigest: hex_digest, FilePath: file_path}, nil
}

type RepoStat struct {
	DelPaths []string
	ModPaths []string
	NewPaths []string
	UnkPaths []string
}

func Status(repo_file, work_tree string) (*RepoStat, error) {
	real_work_tree, err := file_ignore.GetWorkTreeRoot(work_tree)
	if err != nil {
		return nil, err
	}
	log.Debug.Printf("Real worktree %v", real_work_tree)
	stat := new(RepoStat)
	err = file_ignore.WalkWorktree(
		real_work_tree,
		real_work_tree,
		func(worktree_root, fpath string, d fs.DirEntry, err error) error {
			if !d.IsDir() {
				rel, _ := filepath.Rel(worktree_root, fpath)
				stat.ModPaths = append(stat.ModPaths, rel)
			}
			return nil
		},
		file_ignore.DefaultIgnoreFunc,
	)
	if err != nil {
		return nil, err
	}
	return stat, nil
}
