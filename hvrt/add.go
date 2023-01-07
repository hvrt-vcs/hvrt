package hvrt

import (
	"bytes"
	"context"
	"database/sql"
	"fmt"
	"io"
	"io/fs"
	"log"
	"os"
	"strings"

	// "fmt"
	"encoding/hex"

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
func AddFile(work_tree, file_path string, tx *sql.Tx) error {
	// FIXME: alternatively, check that absolute paths point to files within
	// worktree.

	// We only want the path relative to the repo worktree.
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

	full_file_path := filepath.Join(work_tree, file_path)
	file_reader, err := os.Open(full_file_path)
	if err != nil {
		return err
	}
	defer file_reader.Close()

	hash := sha3.New256()
	_, err = io.Copy(hash, file_reader)
	if err != nil {
		return err
	}

	file_hex_digest := hex.EncodeToString(hash.Sum([]byte{}))
	hash.Reset()

	fstat, err := file_reader.Stat()
	if err != nil {
		return err
	}

	_, err = tx.Exec(blob_script, file_hex_digest, "sha3-256", fstat.Size())
	if err != nil {
		return err
	}

	// To be cross platform, we normalize the path with forward slashes.
	_, err = tx.Exec(file_script, filepath.ToSlash(file_path), file_hex_digest, "sha3-256", fstat.Size())
	if err != nil {
		return err
	}

	chunk_stmt, err := tx.Prepare(blob_chunk_script)
	if err != nil {
		return err
	}

	// rewind file to beginning
	if _, err = file_reader.Seek(0, 0); err != nil {
		return err
	}

	// Save time/space with a reused digest slice. See the following link for
	// clarification: https://yourbasic.org/golang/clear-slice/
	digest_bytes := make([]byte, 0)

	// TODO: pull this chunk size from config
	// 8KiB
	chunk_size := int64(1024 * 8)
	// chunk_size := int64(1) // For testing

	buffer := bytes.NewBuffer(make([]byte, 0, chunk_size))
	compressor, err := zstd.NewWriter(buffer)
	if err != nil {
		return err
	}

	for cur_byte, num := int64(0), int64(0); cur_byte < fstat.Size(); cur_byte += num {
		// Retain underlying capacity from previous loop iteration, but set
		// length to zero.
		digest_bytes = digest_bytes[:0]
		buffer.Reset()

		hash.Reset()
		compressor.Reset(buffer)
		multi_writer := io.MultiWriter(hash, compressor)
		section_reader := io.NewSectionReader(file_reader, cur_byte, chunk_size)

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

		chunk_hex_digest := hex.EncodeToString(hash.Sum(digest_bytes))

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

func appendRelPath(paths []string, work_tree, maybe_child string) ([]string, error) {
	rel_path, err := filepath.Rel(work_tree, maybe_child)
	if err != nil {
		return paths, err
	}
	if strings.HasPrefix(rel_path, "..") || filepath.IsAbs(rel_path) {
		return paths, fmt.Errorf(`path "%v" outside work tree "%v"`, maybe_child, work_tree)
	}
	paths = append(paths, rel_path)

	return paths, nil
}

func cleanPaths(work_tree string, file_paths []string) (abs_work_tree string, rel_file_paths []string, ret_err error) {
	abs_wt, err := filepath.Abs(work_tree)
	if err != nil {
		return "", nil, err
	}
	return_paths := make([]string, 0, len(file_paths))

	for _, p := range file_paths {
		abs_p, err := filepath.Abs(p)
		if err != nil {
			return abs_wt, return_paths, err
		}

		p_stat, err := os.Stat(abs_p)
		if err != nil {
			return abs_wt, return_paths, err
		}

		// TODO: add .hvrtignore logic in here, along with respecting the
		// `force` flag to override it.
		if !p_stat.IsDir() {
			return_paths, err = appendRelPath(return_paths, abs_wt, abs_p)
			if err != nil {
				return abs_wt, return_paths, err
			}
		} else {
			err = filepath.WalkDir(abs_p,
				func(path string, d fs.DirEntry, err error) error {
					// If we hit errors walking the hierarchy, just print them
					// and keep moving forward.
					if err != nil {
						log.Println(err)
					}

					if !d.IsDir() {
						return_paths, err = appendRelPath(return_paths, abs_wt, path)
						if err != nil {
							return err
						}
					}
					return nil
				},
			)
			if err != nil {
				return abs_wt, return_paths, err
			}
		}
	}

	return abs_wt, return_paths, nil
}

func AddFiles(work_tree string, file_paths []string) error {
	abs_work_tree, rel_file_paths, err := cleanPaths(work_tree, file_paths)
	if err != nil {
		return err
	}

	wt_db, err := GetExistingWorktreeDB(abs_work_tree)
	if err != nil {
		return err
	}
	defer wt_db.Close()

	wt_tx, err := wt_db.BeginTx(context.Background(), nil)
	if err != nil {
		return err
	}

	for _, add_path := range rel_file_paths {
		err = AddFile(abs_work_tree, add_path, wt_tx)
		if err != nil {
			tx_err := wt_tx.Rollback()
			if tx_err != nil {
				log.Println("Error rolling back transaction:", tx_err)
			}
			return err
		}
	}

	return wt_tx.Commit()
}
