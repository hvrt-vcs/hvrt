package file_ignore

import (
	"bufio"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/bmatcuk/doublestar/v4"
	"github.com/hvrt-vcs/hvrt/log"
	// "modernc.org/sqlite"
)

var (
	true_bool  *bool
	false_bool *bool
)

// init sets initial values for variables used in the package.
func init() {
	true_bool, false_bool = new(bool), new(bool)
	*true_bool = true
	*false_bool = false
}

type IgnorePattern struct {
	IgnoreRoot      string
	OriginalPattern string
	Pattern         string
	AsDir           bool
	Rooted          bool
	Negated         bool
}

func FnMatchCase(name, pat string) (bool, error) {
	name = filepath.ToSlash(name)

	// doublestar.Match identically across Windows and POSIX systems.
	return doublestar.Match(pat, name)
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

// TODO: more closely match gitignore rules. For example, inverse rules starting
// with `!`, etc. See URL: https://git-scm.com/docs/gitignore
func ParseIgnoreFile(ignore_file_path string) ([]IgnorePattern, error) {

	ignore_file, err := os.Open(ignore_file_path)
	if err != nil {
		log.Warning.Printf("failed to parse ignore file %v", ignore_file_path)
		return nil, err
	}
	defer ignore_file.Close()

	istat, ierr := ignore_file.Stat()
	if ierr != nil {
		return nil, err
	} else if istat.IsDir() {
		return nil, fmt.Errorf(`ignore file %v is a directory`, ignore_file_path)
	}

	ignore_root := filepath.Dir(ignore_file_path)
	log.Debug.Printf("ignore root %v", ignore_root)
	patterns := make([]IgnorePattern, 0)
	scanner := bufio.NewScanner(ignore_file)
	for scanner.Scan() {
		original_text := scanner.Text()
		trimmed := strings.TrimRight(original_text, " \t\n\r\v\f")

		// Ignore empty or commented lines
		if trimmed == "" || strings.HasPrefix(trimmed, "#") {
			continue
		}

		// If there is an escape character at the end, the whitespace needs to be preserved
		if strings.HasSuffix(trimmed, "\\") && len(trimmed) < len(original_text) {
			trimmed = original_text
		}

		cur_pat := IgnorePattern{
			IgnoreRoot:      ignore_root,
			OriginalPattern: original_text,
			Pattern:         trimmed,
			AsDir:           false,
			Rooted:          false,
			Negated:         false,
		}

		// There is a slash in the path somewhere other than the end
		if strings.ContainsRune(strings.TrimRight(cur_pat.Pattern, "/"), '/') {
			cur_pat.Rooted = true
			cur_pat.Pattern = strings.TrimLeft(cur_pat.Pattern, "/")
		}

		if strings.HasSuffix(cur_pat.Pattern, "/") {
			cur_pat.AsDir = true
			cur_pat.Pattern = strings.TrimRight(cur_pat.Pattern, "/")
		}

		if strings.HasPrefix(cur_pat.Pattern, "!") {
			cur_pat.Negated = true
			cur_pat.Pattern = strings.TrimPrefix(cur_pat.Pattern, "!")
		}

		if doublestar.ValidatePattern(cur_pat.Pattern) {
			patterns = append(patterns, cur_pat)
		}
	}

	log.Info.Printf("parsed ignore file %v with patterns %v", ignore_file_path, patterns)

	return patterns, nil
}

func getParentdir(dir string) string {
	if dir == filepath.Dir(dir) {
		return ""
	} else {
		return filepath.Dir(dir)
	}
}

// ReverseInplace reverses a slice in place, then returns it.
func ReverseInplace[T any](slice []T) []T {
	for i, j := 0, len(slice)-1; i < j; i, j = i+1, j-1 {
		slice[i], slice[j] = slice[j], slice[i]
	}

	return slice
}

func ParentDirs(worktree_root, fpath string) []string {
	return_paths := make([]string, 0)
	worktree_root = filepath.Clean(worktree_root)
	fpath = filepath.Clean(fpath)

	if IsRoot(fpath) || worktree_root == fpath {
		return_paths = append(return_paths, fpath)
		return return_paths
	}

	cur_dir := filepath.Dir(fpath)
	for ; !IsRoot(cur_dir) && cur_dir != worktree_root; cur_dir = filepath.Dir(cur_dir) {
		return_paths = append(return_paths, cur_dir)
	}
	// add worktree_root
	return_paths = append(return_paths, cur_dir)

	return_paths = ReverseInplace(return_paths)

	return return_paths
}

func GetWorkTreeRoot(start_dir string) (string, error) {
	abs_path, err := filepath.Abs(start_dir)
	if err != nil {
		return "", err
	}

	cur_dir := abs_path
	for cur_dir != "" {
		log.Debug.Println(cur_dir)
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

type IgnoreCache struct {
	ignore_patterns map[string][]IgnorePattern
	worktree_root   string
}

func NewIgnoreCache(worktree_root string) *IgnoreCache {
	ignore_patterns := make(map[string][]IgnorePattern, 0)
	ic := new(IgnoreCache)
	ic.ignore_patterns = ignore_patterns
	ic.worktree_root = worktree_root
	return ic
}

func (ic *IgnoreCache) MatchesIgnore(fpath string, de fs.DirEntry) bool {
	var err error
	var ignore *bool

	// root and worktree root can never be ignored.
	if IsRoot(fpath) {
		return false
	} else if ic.worktree_root == fpath {
		return false
	}

	for _, par_dir := range ParentDirs(ic.worktree_root, filepath.Dir(fpath)) {
		ignore_dir := filepath.ToSlash(par_dir)
		patterns, present := ic.ignore_patterns[ignore_dir]

		if !present {
			// even if the ignore file doesn't exist, store an empty slice so
			// that we don't hit the file system again the next time we check
			// for this ignore file on a different file with the same ancestor
			// directory.
			pattern_pairs, _ := ParseIgnoreFile(filepath.Join(par_dir, ".hvrtignore"))
			ic.ignore_patterns[ignore_dir] = pattern_pairs
			patterns = pattern_pairs
			present = true
		}

		if present && len(patterns) > 0 {
			for _, pat := range patterns {
				log.Debug.Printf("Checking if path %v is ignored by patterns %v", fpath, patterns)

				// If we already matched for ignore, don't keep checking unless it is a negated pattern.
				// Don't check dir matches against non-dir paths.
				if ignore == true_bool && !pat.Negated {
					continue
				} else if pat.Negated && ignore != true_bool {
					continue
				} else if pat.AsDir && !de.IsDir() {
					continue
				} else {
					var name string
					if pat.Rooted {
						name, err = filepath.Rel(pat.IgnoreRoot, fpath)
						if err != nil {
							log.Error.Println(err)
							continue
						}
						name = filepath.ToSlash(name)
					} else {
						name = de.Name()
					}

					if match, err := FnMatch(pat.Pattern, name); err != nil {
						log.Warning.Printf("skipping malformed ignore pattern: %v", pat)
						continue
					} else if match {
						if pat.Negated {
							ignore = false_bool
						} else {
							ignore = true_bool
						}
					}
				}
			}
		}
	}

	if ignore != nil {
		return *ignore
	} else {
		return false
	}
}

type WalkDirFunc func(worktree_root, fpath string, d fs.DirEntry, err error) error

func IsRoot(fpath string) bool {
	return strings.HasSuffix(filepath.Dir(fpath), string(filepath.Separator))
}

func Parent() {

}

// Skip ignored directories. Do nothing with ignored files.
func DefaultIgnoreFunc(worktree_root, fpath string, d fs.DirEntry, err error) error {
	if d.IsDir() {
		return fs.SkipDir
	} else {
		return nil
	}
}

// Similar to `filepath.WalkDir`, but calls a different func for ignored files.
func WalkWorktree(worktree_root string, fn, fn_ignore WalkDirFunc) error {
	ignore_cache := NewIgnoreCache(worktree_root)

	return filepath.WalkDir(
		worktree_root,
		func(fpath string, d fs.DirEntry, err error) error {
			if ignore_cache.MatchesIgnore(fpath, d) {
				return fn_ignore(worktree_root, fpath, d, err)
			} else {
				return fn(worktree_root, fpath, d, err)
			}
		},
	)
}
