package hvrt

import (
	"database/sql"
	"fmt"
	_ "modernc.org/sqlite"
)

func initSql() {
	sql_db, err := sql.Open("sqlite", ":memory:")
	if err != nil {
		fmt.Println("What went wrong with loading the SQL DB?", err)
		panic("Could not connect to sqlite database.")
	}
	defer sql_db.Close()
	fmt.Println("Did we load the SQL DB?", sql_db)

	initScript, err := SQLFiles.ReadFile("sql/sqlite3/init.sql")
	if err != nil {
		fmt.Println("We screwed up somehow:", err)
		panic("Chickening out...")
	}
	initString := string(initScript)
	fmt.Println("Did we load the init script?", initString)
	result, exec_err := sql_db.Exec(string(initScript), SemanticVersion)
	if exec_err != nil {
		fmt.Println("what went wrong with our init script?", exec_err)
		panic("Chickening out after failed init script...")
	}
	fmt.Println("How did our init script succeed?", result)
}
