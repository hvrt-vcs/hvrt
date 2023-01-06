package hvrt

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

func Commit(work_tree, message, author, committer string) error {
	wt_db, err := GetExistingWorktreeDB(work_tree)
	if err != nil {
		return err
	}
	defer wt_db.Close()

	return nil
}
