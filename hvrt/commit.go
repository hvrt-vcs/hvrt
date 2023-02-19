package hvrt

import (
	"context"
	"database/sql"

	"github.com/hvrt-vcs/hvrt/log"
)

// import (
// 	// "database/sql"
// 	// "os"
// 	// "path/filepath"
// 	// "github.com/klauspost/compress/zstd"
// 	// "database/sql"
// 	// "github.com/uptrace/bun/driver/sqliteshim"
// )

func init() {
}

func SliceContains[T comparable](slc []T, comp T) bool {
	for _, v := range slc {
		if comp == v {
			return true
		}
	}
	return false
}

func innerCommit(work_tree, message, author, committer string, wt_tx, repo_tx *sql.Tx) error {

	var (
		err                   error
		write_chunk_stmt      *sql.Stmt
		write_blob_stmt       *sql.Stmt
		write_blob_chunk_stmt *sql.Stmt
		chunk_rows            *sql.Rows
	)

	// FIXME: do not hardcode this to sqlite
	write_chunk_path := "sql/sqlite/repo/commit/chunk.sql"
	if write_chunk_bytes, err := SQLFiles.ReadFile(write_chunk_path); err != nil {
		return err
	} else if write_chunk_stmt, err = repo_tx.Prepare(string(write_chunk_bytes)); err != nil {
		return err
	}
	defer write_chunk_stmt.Close()

	// FIXME: do not hardcode this to sqlite
	write_blob_path := "sql/sqlite/repo/commit/blob.sql"
	write_blob_bytes, err := SQLFiles.ReadFile(write_blob_path)
	if err != nil {
		return err
	} else if write_blob_stmt, err = repo_tx.Prepare(string(write_blob_bytes)); err != nil {
		return err
	}
	defer write_blob_stmt.Close()

	// FIXME: do not hardcode this to sqlite
	write_blob_chunk_path := "sql/sqlite/repo/commit/blob_chunk.sql"
	write_blob_chunk_bytes, err := SQLFiles.ReadFile(write_blob_chunk_path)
	if err != nil {
		return err
	} else if write_blob_chunk_stmt, err = repo_tx.Prepare(string(write_blob_chunk_bytes)); err != nil {
		return err
	}
	defer write_blob_chunk_stmt.Close()

	// Worktree is always sqlite
	read_chunks_path := "sql/sqlite/work_tree/read_chunks.sql"
	if read_chunks_bytes, err := SQLFiles.ReadFile(read_chunks_path); err != nil {
		return err
	} else if chunk_rows, err = wt_tx.Query(string(read_chunks_bytes)); err != nil {
		return err
	}
	defer chunk_rows.Close()

	var (
		hash             string
		hash_algo        string
		compression_algo string
		data             sql.RawBytes
	)

	for chunk_rows.Next() {
		if err := chunk_rows.Scan(&hash, &hash_algo, &compression_algo, &data); err != nil {
			return err
		}
		log.Debug.Printf("hash: '%v', hash_algo: '%v', compression_algo: '%v', data: '%v'", hash, hash_algo, compression_algo, data)

		if result, err := write_chunk_stmt.Exec(hash, hash_algo, compression_algo, data); err != nil {
			return err
		} else {
			log.Debug.Printf("execution result: %v", result)
		}
	}

	return nil
}

func Commit(work_tree, message, author, committer string) error {
	wt_db, err := GetExistingWorktreeDB(work_tree)
	if err != nil {
		return err
	}
	defer wt_db.Close()

	repo_db, err := GetExistingRepoDB(work_tree)
	if err != nil {
		return err
	}
	defer repo_db.Close()

	wt_tx, err := wt_db.BeginTx(context.Background(), nil)
	if err != nil {
		return err
	}

	repo_tx, err := repo_db.BeginTx(context.Background(), nil)
	if err != nil {
		if err := wt_tx.Rollback(); err != nil {
			log.Error.Println(err)
		}
		return err
	}

	if err := innerCommit(work_tree, message, author, committer, wt_tx, repo_tx); err != nil {
		if err := wt_tx.Rollback(); err != nil {
			log.Error.Println(err)
		}
		if err := repo_tx.Rollback(); err != nil {
			log.Error.Println(err)
		}

		return err
	} else {
		if err := wt_tx.Commit(); err != nil {
			if err := repo_tx.Rollback(); err != nil {
				log.Error.Println(err)
			}
			return err
		}
		if err := repo_tx.Commit(); err != nil {
			return err
		}
	}

	return nil
}
