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
	read_chunks_path := "sql/sqlite/work_tree/read_chunks.sql"
	read_chunks_bytes, err := SQLFiles.ReadFile(read_chunks_path)
	if err != nil {
		return err
	}
	read_chunks := string(read_chunks_bytes)

	// FIXME: do not hardcode this to sqlite
	write_chunk_path := "sql/sqlite/repo/write_chunk.sql"
	write_chunk_bytes, err := SQLFiles.ReadFile(write_chunk_path)
	if err != nil {
		return err
	}
	write_chunk := string(write_chunk_bytes)

	write_chunk_stmt, err := repo_tx.Prepare(write_chunk)
	if err != nil {
		return err
	}
	defer write_chunk_stmt.Close()

	chunk_rows, err := wt_tx.Query(read_chunks)
	if err != nil {
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
		err := chunk_rows.Scan(
			&hash,
			&hash_algo,
			&compression_algo,
			&data,
		)
		if err != nil {
			return err
		}
		log.Debug.Printf(
			"hash: '%v', hash_algo: '%v', compression_algo: '%v', data: '%v'",
			hash,
			hash_algo,
			compression_algo,
			data,
		)

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
		if tx_err := wt_tx.Rollback(); tx_err != nil {
			log.Error.Println(tx_err)
		}
		return err
	}

	if err := innerCommit(work_tree, message, author, committer, wt_tx, repo_tx); err != nil {
		if tx_err := wt_tx.Rollback(); tx_err != nil {
			log.Error.Println(tx_err)
		} else if tx_err := repo_tx.Rollback(); tx_err != nil {
			log.Error.Println(tx_err)
		}

		return err
	} else {
		if tx_err := wt_tx.Commit(); tx_err != nil {
			return tx_err
		} else if tx_err := repo_tx.Commit(); tx_err != nil {
			return tx_err
		}
	}

	return nil
}
