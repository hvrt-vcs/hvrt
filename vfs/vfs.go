package vfs

import (
	"fmt"
	"io"
	stdlib_fs "io/fs"
	"os"
	"path/filepath"
	"strings"
)

func init() {

}

var NotImplementedError error = fmt.Errorf("requested functionality is not implemented")

// A File interface. It is acceptable for any implementation which doesn't
// implement a given method to simply return NotImplementedError for that
// method.
type File interface {
	stdlib_fs.File
	io.Writer
	io.Seeker
}

// CreateFS is the interface that wraps the Create method. It should behave similarly to the os.Create function.
type CreateFS interface {
	stdlib_fs.FS
	Create(name string) (File, error)
}

// OpenFileFS is the interface that wraps the OpenFile method. It need not be able to implement all flags that os.OpenFile supports.
type OpenFileFS interface {
	stdlib_fs.FS
	OpenFile(name string, flag int, perm os.FileMode) (File, error)
}

// RemoveFS is the interface that wraps the Remove method. If a file system cannot remove (i.e. unlink) files under any circumstances, then it should not implment this interface.
type RemoveFS interface {
	stdlib_fs.FS
	Remove(name string) error
}

// RenameFS is the interface that wraps the Rename method. If a file system cannot rename (i.e. move) files under any circumstances, then it should not implment this interface.
type RenameFS interface {
	stdlib_fs.FS
	Rename(oldpath, newpath string) error
}

// An implemententation of `ReadWriteFS` to interact with a real filesystem on the present operating system.
type OSFS struct {
	// ReadWriteFS
	original_root_dir string
	root_dir          string
	is_actually_root  bool
	is_symlink        bool
}

func NewOSFS(root string) (*OSFS, error) {
	original_root_dir := root
	root = filepath.Clean(root)
	info, err := os.Stat(root)
	is_real_root := false
	is_symlink := false
	if err != nil {
		return nil, err
	}

	if !info.IsDir() {
		return nil, fmt.Errorf("path is not directory: %v", root)
	}

	if strings.HasSuffix(filepath.Dir(root), string(filepath.Separator)) {
		is_real_root = true
	}

	if unsymlinked, err := filepath.EvalSymlinks(root); err == nil && unsymlinked != root {
		is_symlink = true
	}

	return &OSFS{
		original_root_dir: original_root_dir,
		root_dir:          root,
		is_actually_root:  is_real_root,
		is_symlink:        is_symlink,
	}, nil

}

func (osfs *OSFS) Open(name string) (stdlib_fs.File, error) {
	return os.Open(filepath.Join(osfs.root_dir, name))
}

func (osfs *OSFS) Stat(name string) (stdlib_fs.FileInfo, error) {
	return os.Stat(filepath.Join(osfs.root_dir, name))
}

func (osfs *OSFS) ReadDir(name string) ([]stdlib_fs.DirEntry, error) {
	return os.ReadDir(filepath.Join(osfs.root_dir, name))
}

func (osfs *OSFS) OpenFile(name string, flag int, perm os.FileMode) (File, error) {
	return os.OpenFile(filepath.Join(osfs.root_dir, name), flag, perm)
}

func (osfs *OSFS) Remove(name string) error {
	return os.Remove(filepath.Join(osfs.root_dir, name))
}

func (osfs *OSFS) Rename(oldpath, newpath string) error {
	return os.Rename(filepath.Join(osfs.root_dir, oldpath), filepath.Join(osfs.root_dir, newpath))
}

func (osfs *OSFS) Rel(name string) (string, error) {
	if filepath.IsAbs(name) {
		return filepath.Rel(osfs.root_dir, name)
	} else {
		return name, nil
	}
}
