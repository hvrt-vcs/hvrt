### Cross Compiling with sqlite3 support
* https://github.com/mattn/go-sqlite3/issues/106
* http://www.limitlessfx.com/cross-compile-golang-app-for-windows-from-linux.html
* https://github.com/mattn/go-sqlite3#faq

### Design ideas
* Since we are using golang, there is a unified interface for connecting to
  different SQL databases. We'll probably still need to deal with DB specific
  syntax and idiosyncracies, but that fine: we just need to write tests that
  are backend agnostic (i.e. they are only looking at the data that comes out
  of the DB, and only use features common to all DBs, such as foreign key
  constraints).
* Since Postgres is most similar to Sqlite, we will start with that as our
  second backend. MySQL and others can come later.
