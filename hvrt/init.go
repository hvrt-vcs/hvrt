package hvrt

import (
	"database/sql"
	_ "modernc.org/sqlite"
)

func Init(repo_file string) error {
	// TODO: create parent directories to file if they do not already exist? Or
	// perhaps just warn and return an error to that effect.
	sql_db, err := sql.Open("sqlite", repo_file)
	if err != nil {
		return err
	}
	defer sql_db.Close()

	initScript, err := SQLFiles.ReadFile("sql/sqlite3/init.sql")
	if err != nil {
		return err
	}

	initString := string(initScript)
	_, err = sql_db.Exec(initString, SemanticVersion)
	if err != nil {
		return err
	}
	return nil
}
