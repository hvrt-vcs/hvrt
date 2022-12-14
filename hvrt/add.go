package hvrt

import (
	"context"
	"database/sql"
	"fmt"
	"os"

	// "errors"
	// "fmt"
	"github.com/klauspost/compress/zstd"
	_ "modernc.org/sqlite"

	// "os"
	"path/filepath"
	// "regexp"
)

func AddFile(work_tree, file_path string, inner_thunk ThunkErr) error {
	work_tree_file := filepath.Join(work_tree, WorkTreeConfigDir, "work_tree_state.sqlite")
	fmt.Println(work_tree_file)
	blob_chunk_script_path := "sql/sqlite/work_tree/add/blob_chunk.sql"
	qparms := CopyOps(SqliteDefaultOpts)

	blob_chunk_script, err := SQLFiles.ReadFile(blob_chunk_script_path)
	if err != nil {
		return err
	}
	blob_chunk_string := string(blob_chunk_script)

	// work tree state is always sqlite
	wt_db, err := sql.Open("sqlite", SqliteDSN(work_tree_file, qparms))
	if err != nil {
		return err
	}
	defer wt_db.Close()

	wt_tx, err := wt_db.BeginTx(context.Background(), nil)
	if err != nil {
		return err
	}

	// ("blob_hash", "blob_hash_algo", "start_byte", "end_byte", "compression_algo", "data")

	encoder, _ := zstd.NewWriter(nil)

	full_file_path := filepath.Join(work_tree, file_path)
	bytes_blob, err := os.ReadFile(full_file_path)
	if err != nil {
		// Ignore rollback errors, for now.
		_ = wt_tx.Rollback()
		return err
	}
	enc_blob := encoder.EncodeAll(bytes_blob, make([]byte, 0))

	_, err = wt_tx.Exec(blob_chunk_string,
		"deadbeef",      // blob_hash
		"sha3-256",      // blob_hash_algo
		0,               // start_byte
		len(bytes_blob), // end_byte
		"zstd",          // compression_algo
		enc_blob,        // data
	)
	if err != nil {
		// Ignore rollback errors, for now.
		_ = wt_tx.Rollback()
		return err
	}

	err = inner_thunk()
	if err != nil {
		// Ignore rollback errors, for now.
		_ = wt_tx.Rollback()
		return prepError(err)
	}
	return wt_tx.Commit()
}
