package hvrt

import (
	"bufio"
	"encoding/hex"
	"errors"
	"io"
	"io/fs"
	"log"
	"os"
	"path/filepath"
	"strings"

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
	io.Copy(hash, source_file)
	digest := hash.Sum([]byte{})
	hex_digest := hex.EncodeToString(digest)
	return FileHashPair{HashAlgo: "sha3-256", HexDigest: hex_digest, FilePath: file_path}, nil
}

func ParseIgnoreFile(ignore_file_path string) []string {
	patterns := make([]string, 0)
	ignore_file, err := os.Open(ignore_file_path)
	if err != nil {
		return patterns
	}
	defer ignore_file.Close()

	istat, ierr := ignore_file.Stat()
	if ierr != nil || istat.IsDir() {
		return patterns
	}

	scanner := bufio.NewScanner(ignore_file)
	for scanner.Scan() {
		trimmed := strings.TrimSpace(scanner.Text())
		if trimmed != "" && !strings.HasPrefix(trimmed, "#") {
			patterns = append(patterns, trimmed)
		}
	}
	if _DEBUG != 0 && len(patterns) > 0 {
		log.Println("Found some patterns:", patterns)
	}
	return patterns
}

func getParentdir(dir string) string {
	if dir == filepath.Dir(dir) {
		return ""
	} else {
		return filepath.Dir(dir)
	}
}

func panicAbs(maybe_rel_path string) string {
	if maybe_rel_path == "" {
		maybe_rel_path = "."
	}

	abs_path, err := filepath.Abs(maybe_rel_path)
	if err != nil {
		panic("Cannot determine absolute path of given work tree.")
	} else {
		return abs_path
	}
}

func GetWorkTreeRoot(start_dir string) string {
	abs_path := panicAbs(start_dir)
	cur_dir := abs_path
	for cur_dir != "" {
		// log.Println(cur_dir)
		cur_dir_fs := os.DirFS(cur_dir).(fs.StatFS)
		if wt_dir_finfo, wt_err := cur_dir_fs.Stat(".hvrt"); wt_err != nil {
			if errors.Is(wt_err, fs.ErrNotExist) {
				cur_dir = getParentdir(cur_dir)
			} else {
				panic(wt_err)
			}
		} else {
			if wt_dir_finfo.IsDir() {
				return cur_dir
			} else {
				cur_dir = getParentdir(cur_dir)
			}
		}
	}
	panic("Could not find hvrt work tree in given directory or parent directories.")
}

type RepoStat struct {
	DelPaths []string
	ModPaths []string
	NewPaths []string
	UnkPaths []string
}

func MatchesIgnore(root, path string, de fs.DirEntry, patterns []string) bool {
	for _, pat := range patterns {
		if strings.HasSuffix(pat, "/") {
			if !de.IsDir() {
				continue
			}
			match, err := filepath.Match(strings.TrimSuffix(pat, "/"), de.Name())
			if err != nil {
				if _DEBUG != 0 {
					log.Println("Skipping malformed ignore pattern:", pat)
				}
				continue
			}
			if match {
				return true
			}
		}
	}
	return false
}

func recurseWorktree(wt_root, cur_dir string, rstat *RepoStat, all_patterns []string) {
	loc_patterns := ParseIgnoreFile(filepath.Join(cur_dir, ".hvrtignore"))
	loc_patterns = append(loc_patterns, all_patterns...)

	dir_entries, err := os.ReadDir(cur_dir)
	if err != nil {
		return
	}

	for _, entry := range dir_entries {
		full_path := filepath.Join(cur_dir, entry.Name())
		if MatchesIgnore(cur_dir, full_path, entry, loc_patterns) {
			if _DEBUG != 0 {
				log.Println("Ignored file:", full_path)
			}
			continue
		}
		if entry.IsDir() {
			recurseWorktree(wt_root, filepath.Join(cur_dir, entry.Name()), rstat, loc_patterns)
		} else {
			rel, _ := filepath.Rel(wt_root, full_path)
			rstat.ModPaths = append(rstat.ModPaths, rel)
		}
	}
}

func Status(repo_file, work_tree string) (RepoStat, error) {
	abs_work_tree := panicAbs(work_tree)
	real_work_tree := GetWorkTreeRoot(abs_work_tree)
	stat := RepoStat{}
	recurseWorktree(real_work_tree, real_work_tree, &stat, []string{".hvrt/"})
	return stat, nil
}
