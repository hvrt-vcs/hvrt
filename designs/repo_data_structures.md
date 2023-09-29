Repo Data Structures
====================

Although Havarti is similar to other distributed version control systems in its
designs, it differs enough that it is worth recording explicitly how it is
structured under the hood.

General data structure notes:
* Hash algorithms are flexible in Havarti. For example, it is not tied down to a
  single algorithm like git is (i.e. sha1). The algorithm name is, along with
  the digest value, part of the lookup key for a data type. This is what makes
  it possible to swap algorithms at any time, even within the same repo. It is
  also used in the hash for parent types.
* Hash ID - a UTF-8 string of the form 
  `<data type>:<hash algorithm>:<hex digest>`. This is cast to bytes to 
  calculate for composite types like trees and commits.

Some of the main data types in Havarti:
* Commit - A commit is a pointer to a tree object and a list of header values.
  Both the tree reference (a hash) and the headers (the key/value pair strings)
  are hashed as part of the hash reference generation for the commit
  - The key of a commit header can contain any character except the equals sign
    (`=`) and newline. Leading and trailing whitespace will be stripped.
    Although equals signs are allowed in the header value, newlines are not.
    Newlines must be encoded or escaped.
  - When hashing, header keys and values are joined by an equals sign and
    headers are delimited by newlines.
  - The hash value of any parent commits is also hashed as part of the
    calculation. This is what makes it a merkle tree. It is hashed in the format
    `parent <commit hash id> <parent type>`. The order of parent commits is the
    order in which they were merged, thus the order matters. Any number of
    parents is supported.
* Tree - a list of paths, file ids, and blob ids. Paths cannot/should not be
  repeated within the same tree. Blobs are just file contents, so those can be
  repeated if file contents match. A tree hash is calculated by hashing the
  path, file id, and blob id for each entry divided by a newline character (i.e.
  `\n`). The values in each line are delimited by tab characters (i.e. `\t`).
  - Should these be sorted or something? What is the ordering here?
* File id - reference to give provenance to paths; another way to say this is: a
  file id tracks its parents file ids which allows us to explicitly know about
  copies and renames.
* Blob - the raw binary data within a file. For the most part, Havarti doesn't
  care about file contents. If blobs differ at the byte level, they are
  different blobs. Blobs are referred to by their  hash value, since this should
  not clash
* Chunk - a chunk is a part of a blob. This is mostly an implementation detail
  to overcome the fact that most SQL DBs (including SQLite and PostgreSQL) have
  limits on the size of a binary blob row type. Although this limit is quite
  large (several GiB at the extreme end), this still isn't ideal as blobs cannot
  be streamed from the databases without some trickery. By dividing blob data
  into chunks, we can use mostly identical logic on all DBs and overcome the
  streaming limitation of SQL DBs by taking small chunks at a time.
  - Within a SQL DB, a blob is a list of ordered chunks. Thus, it is possible
    for chunks to be shared across multiple blobs.
  - Is it worth making chunks a canonical part of the hash calculation and
    merkle tree? This may create a weird situation where blob contents may
    match, but their hashes differ because they were chunked differently at
    different times. Perhaps there is a way to do this that isn't merely hashing
    chunk references to generate the blob hash.
* Annotation - Annotations make modifications to commits after the initial
  commit. They are included in hash calculations for the current commit, but do
  not change previous commit hash calculations, so they are non destructive in
  nature. They can only change header data, not blob or tree data. One can think
  of annotations as non-destructively layer new headers ontop of old headers.
  For example, if a commit authorship was incorrectly attributed to a dev, an
  annotation could layer this change on top of the original commit without
  destroying the original author data that goes into checking merkle tree
  integrity.
  - Open question: which annotation "wins" in a merge situation with annotations
    in both branches?
* Hash ID - a UTF-8 string of the form `<data type>:<hash algorithm>:<hex
  digest>`. This is cast to bytes to calculate for composite types like trees.
