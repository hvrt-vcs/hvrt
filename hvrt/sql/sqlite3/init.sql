-- It is an error if there is more than one entry in this table. We do not
-- directly insert the version value in this init script so that we avoid
-- updating the script with every release of the software.
CREATE TABLE "vcs_version" (
	"id"	INTEGER,
	"version"	TEXT NOT NULL, -- semantic version
	"created_at" INTEGER DEFAULT unixepoch(CURRENT_TIMESTAMP),
	"modified_at" INTEGER DEFAULT unixepoch(CURRENT_TIMESTAMP),
	PRIMARY KEY("id" AUTOINCREMENT)
)

CREATE TABLE "tags" (
	"id"	INTEGER,
	"name"	TEXT NOT NULL,
	"annotation"	TEXT,
	"is_hidden" BOOLEAN NOT NULL DEFAULT FALSE,
	"is_branch" BOOLEAN NOT NULL DEFAULT FALSE,
	"created_at" INTEGER DEFAULT unixepoch(CURRENT_TIMESTAMP),
	PRIMARY KEY("id" AUTOINCREMENT)
)

-- It is theoretically possible to have a single tree shared between multiple
-- commits. This can happen under the following conditions: the file IDs and
-- associated blob IDs are identical (since these are the only values hashed to
-- generate the tree ID). The values are sorted by the file ID path, then hashed
-- on file ID hash (as a UTF8 hex string) and blob ID hash (as a UTF8 hex
-- string), in that order.
CREATE TABLE "trees" (
	"id"	INTEGER,
	"hash_algo"	TEXT NOT NULL,
	"hash"	TEXT NOT NULL,
	UNIQUE("hash_algo", "hash")
	PRIMARY KEY("id" AUTOINCREMENT)
)

CREATE INDEX tree_hash_algos_idx ON trees("hash_algo");
CREATE INDEX tree_hashes_idx ON trees("hash");

CREATE TABLE "commits" (
	"id"	INTEGER,
	"hash_algo"	TEXT NOT NULL,
	"hash"	TEXT NOT NULL,
	"time"	INTEGER NOT NULL, -- seconds since the unix epoch in UTC

	-- "tz_offset" is used to shift "time" by the given UTC offset (mostly for
	-- display purposes). A `NULL` offset is considered "localtime"; for sorting
	-- purposes "localtime" is treated as UTC (since we have no way of knowing
	-- what it actually is).
	"tz_offset"	INTEGER,  -- Should this be taken into account for hashing?
	"message"	TEXT NOT NULL,
	"committer"	TEXT NOT NULL,
	"author"	TEXT NOT NULL,
	"tree_id"	INTEGER NOT NULL,
	UNIQUE("hash_algo", "hash")
	PRIMARY KEY("id" AUTOINCREMENT)
	FOREIGN KEY ("tree_id") REFERENCES "trees" ("id") ON DELETE RESTRICT
)

CREATE INDEX commit_hash_algos_idx ON commits("hash_algo");
CREATE INDEX commit_hashes_idx ON commits("hash");
CREATE INDEX commit_times_idx ON commits("time");

CREATE TABLE "commit_tags" (
	"id"	INTEGER,

	-- associated branch names/ids are NOT considered when hashing commits
	"commit_id"	INTEGER NOT NULL,
	"tag_id"	INTEGER NOT NULL,
	UNIQUE("commit_id", "tag_id")
	PRIMARY KEY("id" AUTOINCREMENT)
	FOREIGN KEY ("commit_id") REFERENCES "commits" ("id") ON DELETE RESTRICT
	FOREIGN KEY ("tag_id") REFERENCES "tags" ("id") ON DELETE CASCADE
)

CREATE INDEX tag_commits_idx ON commit_tags("commit_id");
CREATE INDEX commit_tags_idx ON commit_tags("tag_id");

CREATE TABLE "commit_parents" (
	"id"	INTEGER,
	"commit_id"	INTEGER NOT NULL,
	"parent_id"	INTEGER NOT NULL,
	"parent_type"	TEXT CHECK("parent_type" IN ('regular', 'merge', 'cherry_pick', 'replay', 'reorder')) NOT NULL DEFAULT 'regular',
	"order"	INTEGER NOT NULL,
	UNIQUE("commit_id", "parent_id")
	PRIMARY KEY("id" AUTOINCREMENT)
	FOREIGN KEY ("commit_id") REFERENCES "commits" ("id") ON DELETE RESTRICT
	FOREIGN KEY ("parent_id") REFERENCES "commits" ("id") ON DELETE RESTRICT
)

CREATE INDEX commit_parents_commit_id_idx ON commit_parents("commit_id");
CREATE INDEX commit_parents_parent_id_idx ON commit_parents("parent_id");

-- Bundles can be used in place of squashing to preserve commit history.
CREATE TABLE "bundles" (
	"id"	INTEGER,
	"name"	TEXT NOT NULL,
	"message"	TEXT,
	"created_at" INTEGER DEFAULT unixepoch(CURRENT_TIMESTAMP),
	"modified_at" INTEGER DEFAULT unixepoch(CURRENT_TIMESTAMP),
	UNIQUE("name")
	PRIMARY KEY("id" AUTOINCREMENT)
)

CREATE TABLE "bundle_commits" (
	"id"	INTEGER,
	"bundle_id"	INTEGER NOT NULL,
	"commit_id"	INTEGER NOT NULL,
	"created_at" INTEGER DEFAULT unixepoch(CURRENT_TIMESTAMP),
	PRIMARY KEY("id" AUTOINCREMENT)

	-- A commit should never be part of more than one bundle.
	UNIQUE("commit_id") -- UNIQUE automatically creates an index
	FOREIGN KEY ("bundle_id") REFERENCES "bundles" ("id") ON DELETE CASCADE
	FOREIGN KEY ("commit_id") REFERENCES "commits" ("id") ON DELETE RESTRICT
)

CREATE INDEX bundle_commits_bundle_id_idx ON bundle_commits("bundle_id");

CREATE TABLE "file_ids" (
	"id"	INTEGER,
	"hash_algo"	TEXT NOT NULL,
	"hash"	TEXT NOT NULL,
	"path"	TEXT NOT NULL,
	UNIQUE("hash_algo", "hash")
	PRIMARY KEY("id" AUTOINCREMENT)
)

-- If a given file_id has no parents, it was created "ex nihilo".
CREATE TABLE "file_id_parents" (
	"id"	INTEGER,
	"file_id"	INTEGER NOT NULL,
	"parent_id"	INTEGER NOT NULL,
	"order"	INTEGER NOT NULL,
	UNIQUE("file_id", "parent_id")
	PRIMARY KEY("id" AUTOINCREMENT)
	FOREIGN KEY ("file_id") REFERENCES "file_ids" ("id")
	FOREIGN KEY ("parent_id") REFERENCES "file_ids" ("id")
)

CREATE INDEX file_id_parents_file_id_idx ON file_id_parents("file_id");
CREATE INDEX file_id_parents_parent_id_idx ON file_id_parents("parent_id");

CREATE TABLE "blobs" (
	"id"	INTEGER,
	"hash_algo"	TEXT NOT NULL,
	"hash"	TEXT NOT NULL,
	"byte_length"	INTEGER NOT NULL,
	UNIQUE("hash_algo", "hash")
	PRIMARY KEY("id" AUTOINCREMENT)
)

CREATE TABLE "tree_members" (
	"id"	INTEGER,
	"tree_id"	INTEGER NOT NULL,
	"file_id"	INTEGER NOT NULL,
	"blob_id"	INTEGER NOT NULL,
	UNIQUE("tree_id", "file_id")
	PRIMARY KEY("id" AUTOINCREMENT)
	FOREIGN KEY ("tree_id") REFERENCES "trees" ("id")
	FOREIGN KEY ("file_id") REFERENCES "file_ids" ("id")
	FOREIGN KEY ("blob_id") REFERENCES "blobs" ("id")
)

CREATE INDEX tree_members_tree_id_idx ON tree_members("tree_id");
CREATE INDEX tree_members_file_id_idx ON tree_members("file_id");
CREATE INDEX tree_members_blob_id_idx ON tree_members("blob_id");

-- Each blob chunk is compressed individually, so that we can decompress them
-- individually later when streaming them.
CREATE TABLE "blob_chunks" (
	"id"	INTEGER,
	"blob_id"	INTEGER NOT NULL,

	-- there is no simple constraint to check that start and end byte indices
	-- don't overlap between sibling blob chunks, so this will likely need to be
	-- checked by a more complicated expression in the SQL code at the time of
	-- insertion. Or just have a consistency check that can be run lazily
	-- "offline".

	-- The benefit of using start and end indices is that we can change the chunk
	-- size in the configuration and we don't need to rebuild previous entries in
	-- the database for the logic to keep working correctly.
	"start_byte"	INTEGER NOT NULL,
	"end_byte"	INTEGER NOT NULL,
	"compression_algo"	TEXT, -- may be NULL to indicate uncompressed data
	"data"	BLOB NOT NULL,
	PRIMARY KEY("id" AUTOINCREMENT)
	FOREIGN KEY ("blob_id") REFERENCES "blobs" ("id")
)

CREATE INDEX blob_chunks_blob_id_idx ON blob_chunks("blob_id");
CREATE INDEX blob_chunks_start_byte_idx ON blob_chunks("start_byte");
CREATE INDEX blob_chunks_end_byte_idx ON blob_chunks("end_byte");
