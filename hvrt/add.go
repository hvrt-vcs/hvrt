package hvrt

import (
	"context"
	"database/sql"
	"fmt"
	"io"
	"os"

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
	work_tree_file := filepath.Join(work_tree, WorkTreeConfigDir, "work_tree_state.sqlite")
	fmt.Println(work_tree_file)

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

	file_digest := hash.Sum([]byte{})
	file_hex_digest := hex.EncodeToString(file_digest)
	hash.Reset()

	fstat, err := file_reader.Stat()
	if err != nil {
		return err
	}

	_, err = tx.Exec(blob_script, file_hex_digest, "sha3-256", fstat.Size())
	if err != nil {
		return err
	}

	// TODO: normalize the path with forward slashes, etc.
	// We only want the path relative to the repo worktree
	_, err = tx.Exec(file_script, file_path, file_hex_digest, "sha3-256", fstat.Size())
	if err != nil {
		return err
	}

	// rewind file to beginning
	_, err = file_reader.Seek(0, 0)
	if err != nil {
		return err
	}

	chunk_stmt, err := tx.Prepare(blob_chunk_script)
	if err != nil {
		return err
	}

	encoder, _ := zstd.NewWriter(nil)

	// TODO: pull this chunk size from config
	// 64KiB
	chunk_bytes := make([]byte, 1024*64)
	var cur_byte uint64 = 0
	for {
		num, err := file_reader.Read(chunk_bytes)
		if err != nil {
			if err == io.EOF {
				break
			} else {
				return err
			}
		}

		_, err = hash.Write(chunk_bytes[:num])
		if err != nil {
			return err
		}

		chunk_hex_digest := hex.EncodeToString(hash.Sum([]byte{}))
		hash.Reset()

		enc_blob := encoder.EncodeAll(chunk_bytes[:num], make([]byte, 0))

		_, err = chunk_stmt.Exec(
			file_hex_digest,  // 1. blob_hash
			"sha3-256",       // 2. blob_hash_algo
			chunk_hex_digest, // 3. chunk_hash
			"sha3-256",       // 4. chunk_hash_algo
			cur_byte,         // 5. start_byte
			num,              // 6. end_byte
			"zstd",           // 7. compression_algo
			enc_blob,         // 8. data
		)

		if err != nil {
			return err
		}

		cur_byte += uint64(num)
	}

	// TODO: insert blob hash for entire file, as well as file path at the end
	// before committing transaction.

	return nil
}

func AddFiles(work_tree string, file_paths []string) error {
	work_tree_file := filepath.Join(work_tree, WorkTreeConfigDir, "work_tree_state.sqlite")
	fmt.Println(work_tree_file)
	qparms := CopyOps(SqliteDefaultOpts)

	// The default mode is "rwc", which will create the file if it doesn't
	// already exist. This is NOT what we want. We want to fail loudly if the
	// file does not exist already.
	qparms["mode"] = "rw"

	// work tree state is always sqlite
	wt_db, err := sql.Open(SQLDialectToDrivers["sqlite"], SqliteDSN(work_tree_file, qparms))
	if err != nil {
		return err
	}
	defer wt_db.Close()

	// sqlite will not throw an error regarding a DB files not exising until we
	// actually attempt to interact with the database, so we need to explicitly
	// check whether it exists. We do this after opening the database connection
	// to avoid a race condition where someone else could either create/delete
	// the file between our existence check and the opening of the connection.
	_, err = os.Stat(work_tree_file)
	if err != nil {
		return err
	}

	wt_tx, err := wt_db.BeginTx(context.Background(), nil)
	if err != nil {
		return err
	}

	for _, add_path := range file_paths {
		err = AddFile(work_tree, add_path, wt_tx)
		if err != nil {
			tx_err := wt_tx.Rollback()
			if tx_err != nil {
				fmt.Println("Error rolling back transaction:", tx_err)
			}
			return err
		}
	}

	return wt_tx.Commit()
}
