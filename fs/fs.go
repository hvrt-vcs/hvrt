package fs

import (
	"fmt"
	"io"
	stdlib_fs "io/fs"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func init() {

}

var NotImplementedError error = fmt.Errorf("requested functionality is not implemented")

type BasicFile interface {
	stdlib_fs.File
}

// An File interface. It is acceptable for any implementation which doesn't implement
type File interface {
	Chmod(mode stdlib_fs.FileMode) error
	Close() error
	Read(b []byte) (n int, err error)
	ReadAt(b []byte, off int64) (n int, err error)
	ReadFrom(r io.Reader) (n int64, err error)
	Seek(offset int64, whence int) (ret int64, err error)
	SetDeadline(t time.Time) error
	SetReadDeadline(t time.Time) error
	SetWriteDeadline(t time.Time) error
	Stat() (stdlib_fs.FileInfo, error)
	Sync() error
	Truncate(size int64) error
	Write(b []byte) (n int, err error)
	WriteAt(b []byte, off int64) (n int, err error)
}

type OpenFileFS interface {
	stdlib_fs.FS
	stdlib_fs.StatFS

	OpenFile(name string, flag int, perm os.FileMode) (File, error)
}

// An FS interface that can, more or less, emulate a real filesystem
type FullFS interface {
	OpenFileFS
	stdlib_fs.ReadDirFS
	Rel(name string) (string, error)
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

func (osfs *OSFS) Rel(name string) (string, error) {
	if filepath.IsAbs(name) {
		return filepath.Rel(osfs.root_dir, name)
	} else {
		return name, nil
	}
}
