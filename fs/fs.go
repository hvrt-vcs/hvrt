package fs

import (
	"fmt"
	"io"
	stdlib_fs "io/fs"
	"os"
	"path/filepath"
	"strings"
	"syscall"
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
	Chdir() error
	Chown(uid int, gid int) error
	Close() error
	Name() string
	Read(b []byte) (n int, err error)
	ReadAt(b []byte, off int64) (n int, err error)
	ReadDir(n int) ([]stdlib_fs.DirEntry, error)
	ReadFrom(r io.Reader) (n int64, err error)
	Readdir(n int) ([]stdlib_fs.FileInfo, error)
	Readdirnames(n int) (names []string, err error)
	Seek(offset int64, whence int) (ret int64, err error)
	SetDeadline(t time.Time) error
	SetReadDeadline(t time.Time) error
	SetWriteDeadline(t time.Time) error
	Stat() (stdlib_fs.FileInfo, error)
	Sync() error
	SyscallConn() (syscall.RawConn, error)
	Truncate(size int64) error
	Write(b []byte) (n int, err error)
	WriteAt(b []byte, off int64) (n int, err error)
	WriteString(s string) (n int, err error)
}

// An FS interface that can, more or less, emulate a real filesystem
type ReadWriteFS interface {
	stdlib_fs.FS
	stdlib_fs.StatFS
	stdlib_fs.ReadDirFS

	OpenFile(name string, flag int, perm os.FileMode) (File, error)
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
