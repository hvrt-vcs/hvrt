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

type fileToAdd struct {
	path             sql.NullString
	blob_hash        sql.NullString
	blob_hash_algo   sql.NullString
	size             sql.NullInt64
	added_at         sql.NullInt64
	chunk_hash       sql.NullString
	chunk_hash_algo  sql.NullString
	start_byte       sql.NullInt64
	end_byte         sql.NullInt64
	compression_algo sql.NullString
	data             []byte
}

func SliceContains[T comparable](slc []T, comp T) bool {
	for _, v := range slc {
		if comp == v {
			return true
		}
	}
	return false
}

func Commit(work_tree, message, author, committer string) error {
	wt_db, err := GetExistingWorktreeDB(work_tree)
	if err != nil {
		return err
	}
	defer wt_db.Close()

	lr_db, err := GetExistingLocalRepoDB(work_tree)
	if err != nil {
		return err
	}
	defer lr_db.Close()

	wt_tx, err := wt_db.BeginTx(context.Background(), nil)
	if err != nil {
		return err
	}

	lr_tx, err := lr_db.BeginTx(context.Background(), nil)
	if err != nil {
		wt_tx.Rollback()
		return err
	}

	rows, err := wt_db.Query(
		`SELECT path, blob_chunks.blob_hash, blob_chunks.blob_hash_algo, size, added_at, blob_chunks.chunk_hash, blob_chunks.chunk_hash_algo, blob_chunks.start_byte, blob_chunks.end_byte, chunks.compression_algo, chunks.data FROM staged_to_add
LEFT OUTER JOIN blob_chunks ON (staged_to_add.blob_hash = blob_chunks.blob_hash AND staged_to_add.blob_hash_algo = blob_chunks.blob_hash_algo)
LEFT OUTER JOIN chunks ON (blob_chunks.chunk_hash = chunks.hash AND blob_chunks.chunk_hash_algo = chunks.hash_algo)`,
	)
	if err != nil {
		return err
	}
	defer rows.Close()

	files := make([]fileToAdd, 0)

	for rows.Next() {
		file := fileToAdd{}
		err := rows.Scan(
			&file.path,
			&file.blob_hash,
			&file.blob_hash_algo,
			&file.size,
			&file.added_at,
			&file.chunk_hash,
			&file.chunk_hash_algo,
			&file.start_byte,
			&file.end_byte,
			&file.compression_algo,
			&file.data,
		)
		if err != nil {
			wt_tx.Rollback()
			lr_tx.Rollback()
			return err
		}
		files = append(files, file)
		log.Debug.Println("sqlite worktree DB row:", file)
	}
	log.Debug.Println("sqlite worktree DB rows:", files)

	wt_tx.Commit()
	lr_tx.Commit()
	return nil
}
