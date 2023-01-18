package hvrt

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

	"github.com/hvrt-vcs/hvrt/file_ignore"

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

func ParseIgnoreFile(ignore_file_path string) (map[string]bool, map[string]bool, error) {
	local_patterns, global_patterns := make(map[string]bool, 0), make(map[string]bool, 0)
	patterns := make([]string, 0)
	ignore_file, err := os.Open(ignore_file_path)
	if err != nil {
		return nil, nil, err
	}
	defer ignore_file.Close()

	istat, ierr := ignore_file.Stat()
	if ierr != nil {
		return nil, nil, err
	} else if istat.IsDir() {
		return nil, nil, fmt.Errorf(`ignore file %v is a directory`, ignore_file_path)
	}

	scanner := bufio.NewScanner(ignore_file)
	for scanner.Scan() {
		trimmed := strings.TrimSpace(scanner.Text())
		matches_dir_only := false
		local_only := false
		if trimmed == "" && strings.HasPrefix(trimmed, "#") {
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
		patterns = append(patterns, trimmed)

	}
	if _DEBUG != 0 && len(patterns) > 0 {
		log.Println("Found some patterns:", patterns)
	}
	return local_patterns, global_patterns, nil
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

// FIXME: instead of raising panic, return error.
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

func MatchesIgnore(root, fpath string, de fs.DirEntry, patterns map[string]bool) bool {
	for pat, match_as_dir := range patterns {
		if match_as_dir && !de.IsDir() {
			continue
		} else {
			match, err := FnMatch(pat, de.Name())
			if err != nil {
				log.Println("Skipping malformed ignore pattern:", pat)
				continue
			}
			if match {
				return true
			}
		}
	}
	return false
}

// walkWorktree recursively descends path, calling walkDirFn.
func walkWorktree(path string, d fs.DirEntry, walkDirFn, walkDirFnIgnore fs.WalkDirFunc) error {
	if err := walkDirFn(path, d, nil); err != nil || !d.IsDir() {
		if err == filepath.SkipDir && d.IsDir() {
			// Successfully skipped directory.
			err = nil
		}
		return err
	}

	// FIXME: doesn't prevent recursing into symbolic links
	dirs, err := fs.ReadDir(os.DirFS(path), ".")
	if err != nil {
		// Second call, to report ReadDir error.
		err = walkDirFn(path, d, err)
		if err != nil {
			if err == filepath.SkipDir && d.IsDir() {
				err = nil
			}
			return err
		}
	}

	for _, d1 := range dirs {
		path1 := filepath.Join(path, d1.Name())
		if err := walkWorktree(path1, d1, walkDirFn, walkDirFnIgnore); err != nil {
			if err == filepath.SkipDir {
				break
			}
			return err
		}
	}
	return nil
}

type statDirEntry struct {
	info fs.FileInfo
}

func (d *statDirEntry) Name() string               { return d.info.Name() }
func (d *statDirEntry) IsDir() bool                { return d.info.IsDir() }
func (d *statDirEntry) Type() fs.FileMode          { return d.info.Mode().Type() }
func (d *statDirEntry) Info() (fs.FileInfo, error) { return d.info, nil }

// Modeled after WalkDir, but ignores ignorable files.
func WalkWorktree(root string, fn, fn_ignore fs.WalkDirFunc) error {
	return file_ignore.WalkWorktree(root, nil, nil)
}

func recurseWorktree(wt_root, cur_dir string, rstat *RepoStat, all_patterns map[string]bool) {
	loc_patterns, global_patterns, _ := ParseIgnoreFile(filepath.Join(cur_dir, ".hvrtignore"))

	for pat, match_as_dir := range global_patterns {
		all_patterns[pat] = match_as_dir
	}

	local_plus_global := make(map[string]bool, 0)
	for pat, match_as_dir := range all_patterns {
		local_plus_global[pat] = match_as_dir
	}
	for pat, match_as_dir := range loc_patterns {
		local_plus_global[pat] = match_as_dir
	}

	dir_entries, err := os.ReadDir(cur_dir)
	if err != nil {
		return
	}

	for _, entry := range dir_entries {
		full_path := filepath.Join(cur_dir, entry.Name())
		if MatchesIgnore(cur_dir, full_path, entry, local_plus_global) {
			if _DEBUG != 0 {
				log.Println("Ignored file:", full_path)
			}
			continue
		}
		if entry.IsDir() {
			recurseWorktree(wt_root, filepath.Join(cur_dir, entry.Name()), rstat, all_patterns)
		} else {
			rel, _ := filepath.Rel(wt_root, full_path)
			rstat.ModPaths = append(rstat.ModPaths, rel)
		}
	}
}

func Status(repo_file, work_tree string) (*RepoStat, error) {
	real_work_tree, err := file_ignore.GetWorkTreeRoot(work_tree)
	if err != nil {
		return nil, err
	}
	stat := &RepoStat{}
	err = file_ignore.WalkWorktree(
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
