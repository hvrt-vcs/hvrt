package hvrt

import (
	"context"
	"database/sql"
	"fmt"
	"io"
	"os"

	// "errors"
	// "fmt"
	"encoding/hex"

	"github.com/klauspost/compress/zstd"
	"golang.org/x/crypto/sha3"

	// "os"
	"path/filepath"
	// "regexp"
)

func AddFile(work_tree, file_path string, inner_thunk ThunkErr) error {
	work_tree_file := filepath.Join(work_tree, WorkTreeConfigDir, "work_tree_state.sqlite")
	fmt.Println(work_tree_file)
	qparms := CopyOps(SqliteDefaultOpts)

	blob_chunk_script_path := "sql/sqlite/work_tree/add/blob_chunk.sql"
	blob_chunk_script_bytes, err := SQLFiles.ReadFile(blob_chunk_script_path)
	if err != nil {
		return err
	}
	blob_chunk_script := string(blob_chunk_script_bytes)

	// blob_script_path := "sql/sqlite/work_tree/add/blob.sql"
	// blob_script_bytes, err := SQLFiles.ReadFile(blob_script_path)
	// if err != nil {
	// 	return err
	// }
	// blob_script := string(blob_script_bytes)

	// work tree state is always sqlite
	wt_db, err := sql.Open(SQLDialectToDrivers["sqlite"], SqliteDSN(work_tree_file, qparms))
	if err != nil {
		return err
	}
	defer wt_db.Close()

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

	// rewind file to beginning
	_, err = file_reader.Seek(0, 0)
	if err != nil {
		return err
	}

	wt_tx, err := wt_db.BeginTx(context.Background(), nil)
	if err != nil {
		return err
	}

	chunk_stmt, err := wt_tx.Prepare(blob_chunk_script)
	if err != nil {
		_ = wt_tx.Rollback()
		return err
	}

	encoder, _ := zstd.NewWriter(nil)
	// 64KiB
	chunk_bytes := make([]byte, 1024*64)
	var cur_byte uint64 = 0
	for {
		num, read_err := file_reader.Read(chunk_bytes)
		if read_err != nil && read_err != io.EOF {
			_ = wt_tx.Rollback()
			return err
		}

		_, err = hash.Write(chunk_bytes[:num])
		if err != nil {
			_ = wt_tx.Rollback()
			return err
		}

		chunk_hex_digest := hex.EncodeToString(hash.Sum([]byte{}))
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

		cur_byte += uint64(num)

		if read_err == io.EOF {
			break
		}
	}

	// TODO: insert blob hash for entire file, as well as file path at the end
	// before committing transaction.

	err = inner_thunk()
	if err != nil {
		// Ignore rollback errors, for now.
		_ = wt_tx.Rollback()
		return prepError(err)
	}
	return wt_tx.Commit()
}
