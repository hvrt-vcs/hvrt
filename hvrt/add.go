package hvrt

import (
	"bytes"
	"context"
	"database/sql"
	"fmt"
	"io"
	stdlib_fs "io/fs"

	// "fmt"
	"encoding/hex"

	"github.com/hvrt-vcs/hvrt/file_ignore"
	"github.com/hvrt-vcs/hvrt/fs"
	"github.com/hvrt-vcs/hvrt/log"
	"github.com/klauspost/compress/zstd"
	"golang.org/x/crypto/sha3"

	// "os"
	"path/filepath"
	// "regexp"
)

// FIXME: pass prepared statements as a map or something, so that they can be
// bound to the transaction and be reused/cached across multiple calls to the
// singular `AddFile` function, instead of being prepared again each time the
// function is called. Reusing prepared statements this way, we should see a big
// performance increase, which will make a difference when we are adding lots of
// files within a single transaction.
func AddFile(file_to_add io.ReadSeeker, file_path string, tx *sql.Tx) error {
	// `AddFiles`` should already have cleaned incoming paths to make sure that
	// they are all relative, but in case this is called directly, we still need
	// to check.
	if filepath.IsAbs(file_path) {
		return fmt.Errorf(`file path is not relative: "%v"`, file_path)
	}

	blob_chunk_script_path := "sql/sqlite/work_tree/add/blob_chunk.sql"
	blob_chunk_script_bytes, err := SQLFiles.ReadFile(blob_chunk_script_path)
	if err != nil {
		return err
	}
	blob_chunk_script := string(blob_chunk_script_bytes)

	blob_script_path := "sql/sqlite/work_tree/add/blob.sql"
	blob_script_bytes, err := SQLFiles.ReadFile(blob_script_path)
	if err != nil {
		return err
	}
	blob_script := string(blob_script_bytes)

	file_script_path := "sql/sqlite/work_tree/add/file.sql"
	file_script_bytes, err := SQLFiles.ReadFile(file_script_path)
	if err != nil {
		return err
	}
	file_script := string(file_script_bytes)

	// rewind file to beginning
	if _, err = file_to_add.Seek(0, io.SeekStart); err != nil {
		return err
	}

	hash := sha3.New256()
	file_size, err := io.Copy(hash, file_to_add)
	if err != nil {
		return err
	}

	// Save time/space with a reused digest slice. See the following link for
	// clarification: https://yourbasic.org/golang/clear-slice/
	digest_bytes := hash.Sum(make([]byte, 0))
	file_hex_digest := hex.EncodeToString(digest_bytes)
	hash.Reset()

	_, err = tx.Exec(blob_script, file_hex_digest, "sha3-256", file_size)
	if err != nil {
		return err
	}

	// To be cross platform, we normalize the path with forward slashes.
	_, err = tx.Exec(file_script, filepath.ToSlash(file_path), file_hex_digest, "sha3-256", file_size)
	if err != nil {
		return err
	}

	chunk_stmt, err := tx.Prepare(blob_chunk_script)
	if err != nil {
		return err
	}

	// rewind file to beginning
	if _, err = file_to_add.Seek(0, io.SeekStart); err != nil {
		return err
	}

	// TODO: pull this chunk size from config. Default should probably be 1MiB
	// to match zstd default window size.
	// 8KiB
	chunk_size := int64(1024 * 8)
	// chunk_size := int64(1) // For testing

	buffer := bytes.NewBuffer(make([]byte, 0, chunk_size))
	compressor, err := zstd.NewWriter(buffer)
	if err != nil {
		return err
	}

	for cur_byte, num := int64(0), int64(0); cur_byte < file_size; cur_byte += num {
		buffer.Reset()
		compressor.Reset(buffer)
		hash.Reset()
		multi_writer := io.MultiWriter(hash, compressor)
		section_reader := io.LimitReader(file_to_add, chunk_size)

		// `num`` should never be less than `1``. First, the for loop condition
		// above should make reading a zero length file impossible. Second, if
		// the `io.Copy` function doesn't fully copy the file (which we already
		// established should be at least `1` byte in length), then an error
		// should be returned here and we immediately return from the function
		// with an error. Thus we can safely subtract a value of `1` from the DB
		// insertion below for this chunk. This ensures that there is not
		// overlap between this chunk and the one following it. It also means
		// that byte ranges are inclusive, not exclusive, of the `end_byte`
		// index value.
		if num, err = io.Copy(multi_writer, section_reader); err != nil {
			return err
		}

		// For now, we always compress chunks, even when leaving them
		// uncompressed would take up slightly less space. This greatly
		// simplifies the logic.
		if err = compressor.Close(); err != nil {
			return err
		}
		enc_blob := buffer.Bytes()

		// Retain underlying capacity, but set length to zero.
		digest_bytes = digest_bytes[:0]
		digest_bytes = hash.Sum(hash.Sum(digest_bytes))
		chunk_hex_digest := hex.EncodeToString(digest_bytes)

		_, err = chunk_stmt.Exec(
			file_hex_digest,  // 1. blob_hash
			"sha3-256",       // 2. blob_hash_algo
			chunk_hex_digest, // 3. chunk_hash
			"sha3-256",       // 4. chunk_hash_algo
			cur_byte,         // 5. start_byte
			cur_byte+num-1,   // 6. end_byte
			"zstd",           // 7. compression_algo
			enc_blob,         // 8. data
		)

		if err != nil {
			return err
		}

		// TODO: figure out if we can take care of all this via constraints, or
		// if we need to do some error inspection based on how constraints are
		// violated.

		// if err != nil {
		// 	// ignore constraint errors
		// 	sqlite_err := err.(*sqlite.Error)
		// 	if sqlite_err.Code() != sqlite3.SQLITE_CONSTRAINT {
		// 		return err
		// 	}
		// }
	}

	return nil
}

func getStatPathFunc(maybe_statfs stdlib_fs.FS) func(path string) (stdlib_fs.FileInfo, error) {
	if wt_statfs, can_be_statfs := maybe_statfs.(stdlib_fs.StatFS); can_be_statfs {
		return wt_statfs.Stat
	} else {
		return func(path string) (stdlib_fs.FileInfo, error) {
			if f, err := maybe_statfs.Open(path); err != nil {
				return nil, err
			} else {
				return f.Stat()
			}
		}
	}
}

func cleanPaths(worktree_fs fs.FullFS, abs_work_tree string, file_paths []string) ([]string, error) {
	all_rel := true
	for _, p := range file_paths {
		if filepath.IsAbs(p) {
			all_rel = false
			break
		}
	}

	rel_paths := make([]string, len(file_paths))
	if all_rel {
		copy(rel_paths, file_paths)
	} else {
		if !filepath.IsAbs(abs_work_tree) {
			return nil, fmt.Errorf("worktree is not absolute path")
		}

		for _, ap := range file_paths {
			rp, err := filepath.Rel(abs_work_tree, ap)
			if err != nil {
				return nil, err
			}
			rel_paths = append(rel_paths, rp)
		}

	}
	statFunc := getStatPathFunc(worktree_fs)
	return_paths := make([]string, 0, len(file_paths))

	for _, rel_path := range rel_paths {
		p_stat, err := statFunc(rel_path)
		if err != nil {
			log.Error.Println(err)
			continue
		}

		if !p_stat.IsDir() {
			return_paths = append(return_paths, rel_path)
		} else {
			err = file_ignore.WalkWorktree(
				worktree_fs,
				rel_path,
				func(worktree_root stdlib_fs.FS, fpath string, d stdlib_fs.DirEntry, err error) error {
					if err != nil {
						// panic(err)
						return err
					}

					if !d.IsDir() {
						return_paths = append(return_paths, fpath)
					}
					return nil
				},

				// TODO: allow ability to forcefully override add .hvrtignore logic in here.
				file_ignore.DefaultIgnoreFunc,
			)

			if err != nil {
				return return_paths, err
			}
		}
	}

	return return_paths, nil
}

func openReadSeekCloser(openfs stdlib_fs.FS, fpath string) (io.ReadSeekCloser, error) {
	file, err := openfs.Open(fpath)
	if err != nil {
		log.Error.Printf("cannot add file %v due to err %v", fpath, err)
		return nil, err
	}

	read_seek_closer, can_read_seek := file.(io.ReadSeekCloser)
	if !can_read_seek {
		defer file.Close()
		err = fmt.Errorf("cannot add file %v because it cannot cast to io.ReadSeekCloser", fpath)
		return nil, err
	}

	return read_seek_closer, nil
}

func AddFiles(work_tree string, file_paths []string) error {
	abs_work_tree, err := filepath.Abs(work_tree)
	if err != nil {
		return err
	}

	// Because of how sqlite works, using a VFS to isn't straightforward at this
	// moment. Just hit the real file system.
	wt_db, err := GetExistingWorktreeDB(abs_work_tree)
	if err != nil {
		return err
	}
	defer wt_db.Close()

	work_tree_fs, err := fs.NewOSFS(abs_work_tree)
	if err != nil {
		return err
	}

	rel_file_paths, err := cleanPaths(work_tree_fs, work_tree, file_paths)
	if err != nil {
		return err
	}

	wt_tx, err := wt_db.BeginTx(context.Background(), nil)
	if err != nil {
		return err
	}

	for _, add_path := range rel_file_paths {
		add_file, err := work_tree_fs.Open(add_path)
		if err != nil {
			log.Error.Println(err)
			continue
		}
		defer add_file.Close()

		stat, err := add_file.Stat()
		if err != nil {
			log.Error.Println(err)
			continue
		}
		if stat.IsDir() {
			err = file_ignore.WalkWorktree(
				work_tree_fs,
				add_path,
				func(worktree_root stdlib_fs.FS, fpath string, d stdlib_fs.DirEntry, err error) error {
					if err != nil {
						log.Debug.Println(err)
						return err
					}

					if !d.IsDir() {
						read_seek_closer, err := openReadSeekCloser(worktree_root, fpath)
						if err != nil {
							return nil
						}
						defer read_seek_closer.Close()
						return AddFile(read_seek_closer, fpath, wt_tx)
					}
					return nil
				},
				file_ignore.DefaultIgnoreFunc,
			)
			if err != nil {
				log.Error.Println(err)
				continue
			}
		} else {
			var read_seek_closer io.ReadSeeker
			if read_seek_closer, err = openReadSeekCloser(work_tree_fs, add_path); err != nil {
				log.Error.Println(err)
				continue
			} else {
				err = AddFile(read_seek_closer, add_path, wt_tx)
				if err != nil {
					log.Error.Println(err)
					continue
				}
			}
		}
		if err != nil {
			tx_err := wt_tx.Rollback()
			if tx_err != nil {
				log.Error.Println("Error rolling back transaction:", tx_err)
			}
			return err
		}
		// Although we made a deferred call to close previously, that won't
		// trigger until we leave the func. To free up potential resources like
		// file descriptors, we call close here as well.
		add_file.Close()
	}

	return wt_tx.Commit()
}
