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
* File renames can be tracked by using a file id (FID). This can be thought of
  like an inode, kind of. FIDs have a source FID (or a parent, if you want). If
  a file is renamed or copied from an existing FID, then the FID it was renamed
  or copied from is its source FID. If an FID was created without a source FID,
  then it's source FID is just null. The FID is pseudorandom: it is a hash
  derived from several values: (1) the file path relative to the root of the
  repo, and (2) the hash of the parent commit(s). These two values should be
  enough to ensure uniqueness and reproducibility. The same FID is referred to
  forever until and if the file is deleted or renamed; a copied file does not
  affect it's source FID. If the file at the same path is recreated in the next
  commit, it receives a new FID (which should be unique since it is derived
  from a unique commit hash, even if the path that is added to the hash is the
  same as before).
    - in a way, there is no real difference between a rename and a copy: if a file
      is copied AND renamed in the same commit, the system sees them equally.
      The system sees them both as derived copies.
