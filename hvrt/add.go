package hvrt

import (
	"context"
	"database/sql"
	"fmt"
	"os"

	// "errors"
	// "fmt"
	"encoding/hex"

	"github.com/klauspost/compress/zstd"
	"golang.org/x/crypto/sha3"

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
	blob_chunk_sql := string(blob_chunk_script)

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

	// TODO: iterate thru file, creating and inserting chunks one at a time.
	encoder, _ := zstd.NewWriter(nil)

	full_file_path := filepath.Join(work_tree, file_path)
	bytes_blob, err := os.ReadFile(full_file_path)
	if err != nil {
		// Ignore rollback errors, for now.
		_ = wt_tx.Rollback()
		return err
	}
	enc_blob := encoder.EncodeAll(bytes_blob, make([]byte, 0))

	hash := sha3.New256()
	_, err = hash.Write(bytes_blob)
	if err != nil {
		return err
	}
	digest := hash.Sum([]byte{})
	hex_digest := hex.EncodeToString(digest)

	_, err = wt_tx.Exec(blob_chunk_sql,
		hex_digest,      // 1. blob_hash
		"sha3-256",      // 2. blob_hash_algo
		hex_digest,      // 3. chunk_hash
		"sha3-256",      // 4. chunk_hash_algo
		0,               // 5. start_byte
		len(bytes_blob), // 6. end_byte
		"zstd",          // 7. compression_algo
		enc_blob,        // 8. data
	)

	// TODO: insert blob hash for entire file, as well as file path at the end
	// before committing transaction.

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
