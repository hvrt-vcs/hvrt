### Cross Compiling with sqlite3 support
* https://github.com/mattn/go-sqlite3/issues/106
* http://www.limitlessfx.com/cross-compile-golang-app-for-windows-from-linux.html
* https://github.com/mattn/go-sqlite3#faq

Signal self chat dump:

For building RDBM backed version control system (ala Fossil, but with support for both SQLite and Postgres, support for arbitrarily large files, and support for explicitly tracking file renames and copies).
* https://github.com/lxwagn/using-go-with-c-libraries

Example of cross compilation with sqlite support:
* https://github.com/go-gitea/gitea/blob/main/Makefile

I need to write a blog post called "git file history considered broken" about why this heuristic approach to file history is so fundamentally broken and wrong for a VCS like git.
* https://github.blog/2022-08-31-gits-database-internals-iii-file-history-queries/

BitKeeper creator Larry McVoy makes the point that git does file renames wrong (I completely agree).
* https://news.ycombinator.com/item?id=9330482

General cross compilation support in golang:
* https://kylewbanks.com/blog/cross-compiling-go-applications-for-multiple-operating-systems-and-architectures
* https://earthly.dev/blog/golang-sqlite/

Does tracking renames making computing rebases and cherry picks properly infeasibly hard?
* https://github.blog/2020-12-17-commits-are-snapshots-not-diffs/

Faster reads of blobs from sqlite:
* https://www.sqlite.org/c3ref/blob_read.html

Sqlite can use memory mapped I/O to be significantly faster:
* https://www.sqlite.org/fasterthanfs.html

Dos and don'ts of VCS design, with GNU arch as the example:
* https://archive.ph/20120714202439/http://sourcefrog.net/weblog/software/vc/arch/whats-wrong.html

Perhaps it should be possible to have file copies/renames have more than one source FID and have them be ordered. This makes it possible to merge multiple files into one file and still keep line history.
* https://fossil-scm.org/forum/forumpost/1bc11a6530b650dd

Diffing in golang:
* https://github.com/sergi/go-diff
* https://github.com/nasdf/diff3

Git's rename threshold:
* https://git-scm.com/docs/diff-options/2.11.4

Create an FS interface that is a representation of the snapshot of a commit (including it's FID). A seperate one for the stage would be good too. It might be possible to use both types and layer them on top of each other to make the next commit (basically overlay the previous commit with the state of the stage). This might not work correctly with multiple parent commits; needs more thought.
* https://pkg.go.dev/io/fs

Perhaps just overlay the stage atop the first parent. When written to storage, the snapshot becomes stand alone (not a diff against it's parent). The FS interface is just for convenience when working in code.
blob hash should be included as well in the metadata for a given file
Create an io.Reader File interface for blobs in the storage. Opening one can be based on hash and hash algorithm. For example `NewBlobReader("deadbeef", algo.SHA3_256)`. It returns the blob it finds as a readable, seekable file-like object or it returns a `FileNotFound` error. Once it is closed, it's DB connection closes too. If it is less than a threshold (user configurable, but defaulting to something biggish, like 16KiB), the entire file is just read into memory, instead of streaming from the DB.
* https://pkg.go.dev/io

High performance Postgres driver for Golang:
* https://github.com/jackc/pgx

Postgres can support large objects up to 4TB in size and can efficiently read/write to them (i.e. only overwrite small chunks or read into the middle of an object instead of reading the whole thing).
* https://www.postgresql.org/docs/current/lo-intro.html

Interesting case study:
* https://levelup.gitconnected.com/how-was-i-build-a-version-control-system-vcs-using-pure-go-83ec8ec5d4f4

Compression and archival in many formats. Pure golang:
* https://pkg.go.dev/github.com/mholt/archiver/v3

For historical compatibility reasons, SQLite has lots of quirks by default:
* https://www.sqlite.org/quirks.html

Binary diffing library in golang:
* https://github.com/kr/binarydist

Well defined binary diff format:
* https://en.m.wikipedia.org/wiki/VCDIFF
