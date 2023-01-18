package file_ignore

import (
	"bufio"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"log"
	"os"
	"path"
	"path/filepath"
	"runtime"
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
	_, err = io.Copy(hash, source_file)
	if err != nil {
		return FileHashPair{}, err
	}

	digest := hash.Sum([]byte{})
	hex_digest := hex.EncodeToString(digest)
	return FileHashPair{HashAlgo: "sha3-256", HexDigest: hex_digest, FilePath: file_path}, nil
}

func FnMatchCase(name, pat string) (bool, error) {
	name = filepath.ToSlash(name)

	// path.Match identically across Windows and POSIX systems.
	return path.Match(pat, name)
}

func FnMatch(name, pat string) (bool, error) {
	if runtime.GOOS == "windows" {
		// The Windows NT and FAT filesystems are treated case insensitively.
		// Force the same behavior here.
		name = strings.ToLower(name)
		pat = strings.ToLower(pat)
	}
	return FnMatchCase(name, pat)
}

func ParseIgnoreFile(ignore_file_path string) (*PatternPairs, error) {
	ignore_file, err := os.Open(ignore_file_path)
	if err != nil {
		return nil, err
	}
	defer ignore_file.Close()

	istat, ierr := ignore_file.Stat()
	if ierr != nil {
		return nil, err
	} else if istat.IsDir() {
		return nil, fmt.Errorf(`ignore file %v is a directory`, ignore_file_path)
	}

	local_patterns, global_patterns := make(map[string]bool, 0), make(map[string]bool, 0)
	scanner := bufio.NewScanner(ignore_file)
	for scanner.Scan() {
		trimmed := strings.TrimSpace(scanner.Text())
		matches_dir_only := false
		local_only := false

		// Ignore empty or commented lines
		if trimmed == "" || strings.HasPrefix(trimmed, "#") {
			continue
		}

		if strings.HasPrefix(trimmed, "/") {
			local_only = true
			trimmed = strings.TrimPrefix(trimmed, "/")
		}
		if strings.HasSuffix(trimmed, "/") {
			matches_dir_only = true
			trimmed = strings.TrimSuffix(trimmed, "/")
		}

		if local_only {
			local_patterns[trimmed] = matches_dir_only
		} else {
			global_patterns[trimmed] = matches_dir_only
		}
	}

	return &PatternPairs{Local: local_patterns, Global: global_patterns}, nil
}

func getParentdir(dir string) string {
	if dir == filepath.Dir(dir) {
		return ""
	} else {
		return filepath.Dir(dir)
	}
}

func ParentDirs(worktree_root, fpath string) []string {
	return_paths := make([]string, 0)
	worktree_root = filepath.Clean(fpath)
	fpath = filepath.Clean(fpath)

	if IsRoot(fpath) || worktree_root == fpath {
		return_paths = append(return_paths, fpath)
		return return_paths
	}

	cur_dir := filepath.Dir(fpath)
	for ; !IsRoot(cur_dir) && cur_dir != worktree_root; cur_dir = filepath.Dir(fpath) {
		return_paths = append(return_paths, cur_dir)
	}
	// add worktree_root
	return_paths = append(return_paths, cur_dir)

	return return_paths
}

func GetWorkTreeRoot(start_dir string) (string, error) {
	abs_path, err := filepath.Abs(start_dir)
	if err != nil {
		return "", err
	}

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
				return cur_dir, nil
			} else {
				cur_dir = getParentdir(cur_dir)
			}
		}
	}
	return "", fmt.Errorf("could not find hvrt work tree in given directory or parent directories: %v", start_dir)
}

type RepoStat struct {
	DelPaths []string
	ModPaths []string
	NewPaths []string
	UnkPaths []string
}

func MatchesIgnore(root, fpath string, de fs.DirEntry, patterns map[string]bool) bool {
	name, err := filepath.Rel(root, fpath)
	if err != nil {
		log.Panicln(err)
	}

	for pat, match_as_dir := range patterns {
		if match_as_dir && !de.IsDir() {
			continue
		} else {
			if match, err := FnMatch(pat, name); err != nil {
				log.Printf("skipping malformed ignore pattern: %v", pat)
				continue
			} else if match {
				return true
			}
		}
	}
	return false
}

type WalkDirFunc func(worktree_root, fpath string, d fs.DirEntry, err error) error

// The string key in the map represents the shell style glob pattern. The bool
// value represents whether the pattern is meant to match for dirs only (i.e.
// the pattern was specified with a trailing slash in the ignore file).
type IgnorePatterns map[string]bool

// The only difference between `Global` and `Local` is that `Local` should only
// match files from the root of the directory where the ignore patterns file was
// specified. `Global` patterns should match at all levels at and below where
// they are specified.
type PatternPairs struct {
	Local  IgnorePatterns
	Global IgnorePatterns
}

func IsRoot(fpath string) bool {
	return strings.HasSuffix(filepath.Dir(fpath), string(filepath.Separator))
}

func Parent() {

}

func DefaultIgnoreFunc(worktree_root, fpath string, d fs.DirEntry, err error) error {
	if d.IsDir() {
		return fs.SkipDir
	} else {
		return nil
	}
}

// Similar to `filepath.WalkDir`, but calls a different func for ignored files.
func WalkWorktree(worktree_root string, fn, fn_ignore WalkDirFunc) error {
	ignore_files := make(map[string]PatternPairs)

	return filepath.WalkDir(
		worktree_root,
		func(fpath string, d fs.DirEntry, err error) error {
			normalized := filepath.ToSlash(filepath.Clean(fpath))
			is_ignored := false

			// root can never be ignored.
			if !IsRoot(fpath) {
				ignore_dir := filepath.ToSlash(filepath.Dir(fpath))
				for _, par_dir := range ParentDirs(worktree_root, filepath.FromSlash(ignore_dir)) {
					ignore_dir = filepath.ToSlash(par_dir)
					patterns, present := ignore_files[ignore_dir]

					// FIXME: this does not account for deeply nested ignores. For example: `my/deeply/hidden/dir/*.ext`
					if present {
						if MatchesIgnore(par_dir, fpath, d, patterns.Local) || MatchesIgnore(par_dir, fpath, d, patterns.Global) {
							is_ignored = true
							break
						}
					}
				}
			}

			if is_ignored {
				return fn_ignore(worktree_root, fpath, d, err)
			} else {
				if d.IsDir() {
					pattern_pairs, parse_err := ParseIgnoreFile(filepath.Join(fpath, ".hvrtignore"))
					if parse_err == nil && pattern_pairs != nil {
						ignore_files[normalized] = *pattern_pairs
					}
				}

				return fn(worktree_root, fpath, d, err)
			}
		},
	)
}
