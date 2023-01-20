package file_ignore

import (
	"bufio"
	"errors"
	"fmt"
	"io/fs"
	"log"
	"os"
	"path"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/bmatcuk/doublestar/v4"
	// "modernc.org/sqlite"
)

// init sets initial values for variables used in the package.
func init() {
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
		return nil, err
	}
	defer ignore_file.Close()

	istat, ierr := ignore_file.Stat()
	if ierr != nil {
		return nil, err
	} else if istat.IsDir() {
		return nil, fmt.Errorf(`ignore file %v is a directory`, ignore_file_path)
	}

	ignore_root := filepath.ToSlash(path.Dir(ignore_file_path))
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

	return patterns, nil
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
	worktree_root = filepath.Clean(worktree_root)
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

	// reverse
	for i, j := 0, len(return_paths)-1; i < j; i, j = i+1, j-1 {
		return_paths[i], return_paths[j] = return_paths[j], return_paths[i]
	}

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

func MatchesIgnore(root, fpath string, de fs.DirEntry, patterns []IgnorePattern) bool {
	ignore := false
	err := error(nil)

	for _, pat := range patterns {
		if pat.AsDir && !de.IsDir() {
			continue
		} else {
			name := de.Name()
			if pat.Rooted {
				name, err = filepath.Rel(pat.IgnoreRoot, fpath)
				if err != nil {
					log.Printf("Could not make path relative: %v", err)
					continue
				}
				name = filepath.ToSlash(name)
			}

			if match, err := FnMatch(pat.Pattern, name); err != nil {
				log.Printf("skipping malformed ignore pattern: %v", pat)
				continue
			} else if match {
				if pat.Negated {
					ignore = false
				} else {
					ignore = true
				}
			}
		}
	}
	return ignore
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
	ignore_files := make(map[string][]IgnorePattern)

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
						if MatchesIgnore(par_dir, fpath, d, patterns) {
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
					if parse_err == nil && len(pattern_pairs) > 0 {
						ignore_files[normalized] = pattern_pairs
					}
				}

				return fn(worktree_root, fpath, d, err)
			}
		},
	)
}
