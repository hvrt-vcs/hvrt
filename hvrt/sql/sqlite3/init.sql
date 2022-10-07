-- It is an error if there is more than one entry in this table. We do not
-- directly hardcode the version value into this init script so that we avoid
-- updating the script with every release of the software.
CREATE TABLE vcs_version (
	"id"	INTEGER,

	-- semantic version
	"version"	TEXT NOT NULL,
	"created_at" INTEGER NOT NULL,
	"modified_at" INTEGER NOT NULL,
	PRIMARY KEY ("id" AUTOINCREMENT)
);

-- Insert the version as a parameter value when we run this init script.
INSERT INTO vcs_version ("version", "created_at", "modified_at")
	VALUES ($1, strftime("%s", CURRENT_TIMESTAMP), strftime("%s", CURRENT_TIMESTAMP));

CREATE TABLE tags (
	"name"	TEXT NOT NULL,
	"annotation"	TEXT,
	"is_hidden" BOOLEAN NOT NULL DEFAULT FALSE,
	"is_branch" BOOLEAN NOT NULL DEFAULT FALSE,
	"created_at" INTEGER NOT NULL DEFAULT CURRENT_TIMESTAMP,
	PRIMARY KEY ("name")
);

-- It is theoretically possible to have a single tree shared between multiple
-- commits. This can happen under the following conditions: the file IDs and
-- associated blob IDs are identical (since these are the only values hashed to
-- generate the tree ID). The values are sorted by the file ID path, then hashed
-- on file ID hash (as a UTF8 hex string) and blob ID hash (as a UTF8 hex
-- string), in that order.
CREATE TABLE trees (
	"hash"	TEXT NOT NULL,
	"hash_algo"	TEXT NOT NULL,
	PRIMARY KEY ("hash", "hash_algo")
);

CREATE TABLE commits (
	"hash"	TEXT NOT NULL,
	"hash_algo"	TEXT NOT NULL,
	"time"	INTEGER NOT NULL, -- seconds since the unix epoch in UTC

	-- "tz_offset" is used to shift "time" by the given UTC offset (mostly for
	-- display purposes).

	-- Should TZ offset be taken into account for hashing?
	"tz_offset_hours"	INTEGER CHECK("tz_offset_hours" BETWEEN -12 AND 12) NOT NULL,
	"tz_offset_minutes"	INTEGER CHECK("tz_offset_minutes" BETWEEN 0 AND 59) NOT NULL,

	"message"	TEXT NOT NULL,
	"committer"	TEXT NOT NULL,
	"author"	TEXT NOT NULL,
	"tree_hash"	TEXT NOT NULL,
	"tree_hash_algo"	TEXT NOT NULL,
	PRIMARY KEY ("hash", "hash_algo")
	FOREIGN KEY ("tree_hash", "tree_hash_algo") REFERENCES "trees" ("hash", "hash_algo") ON DELETE RESTRICT
);

CREATE INDEX commit_times_idx ON commits("time");

CREATE TABLE commit_annotations (
	"id" INTEGER,
	"commit_hash"	TEXT NOT NULL,
	"commit_hash_algo"	TEXT NOT NULL,
	"annotation_committer"	TEXT NOT NULL,
	"annotation_author"	TEXT NOT NULL,
	-- Latest annotation "wins". Previous annotations are listed as "Previous edits".
	"created_at" INTEGER NOT NULL DEFAULT CURRENT_TIMESTAMP,

	-- Start Annotatable fields
	"time"	INTEGER NOT NULL, -- seconds since the unix epoch in UTC
	"tz_offset_hours"	INTEGER CHECK("tz_offset_hours" BETWEEN -12 AND 12) NOT NULL,
	"tz_offset_minutes"	INTEGER CHECK("tz_offset_minutes" BETWEEN 0 AND 59) NOT NULL,

	"message"	TEXT NOT NULL,
	"committer"	TEXT NOT NULL,
	"author"	TEXT NOT NULL,
	-- End Annotatable fields

	PRIMARY KEY ("id" AUTOINCREMENT)
	FOREIGN KEY ("commit_hash", "commit_hash_algo") REFERENCES "commits" ("hash", "hash_algo") ON DELETE RESTRICT
);

CREATE INDEX annotation_hashes_idx ON commit_annotations("commit_hash", "commit_hash_algo");
CREATE INDEX annotation_time_idx ON commit_annotations("time");
CREATE INDEX annotation_creation_idx ON commit_annotations("created_at");

CREATE TABLE commit_tags (
	-- associated branch names/ids are NOT considered when hashing commits
	"commit_hash"	TEXT NOT NULL,
	"commit_hash_algo"	TEXT NOT NULL,
	"tag_name"	TEXT NOT NULL,
	PRIMARY KEY ("commit_hash", "commit_hash_algo", "tag_name")
	FOREIGN KEY ("commit_hash", "commit_hash_algo") REFERENCES "commits" ("hash", "hash_algo") ON DELETE RESTRICT
	FOREIGN KEY ("tag_name") REFERENCES "tags" ("name") ON DELETE CASCADE
);

CREATE INDEX tag_commits_idx ON commit_tags("commit_hash", "commit_hash_algo");
CREATE INDEX commit_tags_idx ON commit_tags("tag_name");

-- If a given commit has no parents, it is a root commit.
-- If a given commit points to parent that does not exist, it is because of a shallow checkout.
CREATE TABLE commit_parents (
	"id"	INTEGER,
	"commit_hash"	TEXT NOT NULL,
	"commit_hash_algo"	TEXT NOT NULL,
	"parent_hash"	TEXT NOT NULL,
	"parent_hash_algo"	TEXT NOT NULL,
	"parent_type"	TEXT CHECK("parent_type" IN ('regular', 'merge', 'cherry_pick', 'replay', 'reorder')) NOT NULL,
	"order"	INTEGER NOT NULL,
	PRIMARY KEY ("commit_hash", "commit_hash_algo", "parent_hash", "parent_hash_algo")
	FOREIGN KEY ("commit_hash", "commit_hash_algo") REFERENCES "commits" ("hash", "hash_algo") ON DELETE RESTRICT
	FOREIGN KEY ("parent_hash", "parent_hash_algo") REFERENCES "commits" ("hash", "hash_algo") ON DELETE RESTRICT
);

CREATE INDEX commit_parents_commit_id_idx ON commit_parents("commit_hash", "commit_hash_algo");
CREATE INDEX commit_parents_parent_id_idx ON commit_parents("parent_hash", "parent_hash_algo");

-- Bundles can be used in place of squashing to preserve commit history. They
-- are ephemeral metadata that is not hashed into the merkle tree.
CREATE TABLE bundles (
	-- The hash of a bundle is the hash of all it's child commit hashes. In what
	-- order should they be hashed? Sorted by hash value before hashing?
	"hash"	TEXT NOT NULL,
	"hash_algo"	TEXT NOT NULL,

	-- Should the above hash include the message and the time? I think probably
	-- yes.
	"message"	TEXT,
	"time" INTEGER DEFAULT CURRENT_TIMESTAMP,
	PRIMARY KEY ("hash", "hash_algo")
);

CREATE TABLE bundle_commits (
	"bundle_hash"	TEXT NOT NULL,
	"bundle_hash_algo"	TEXT NOT NULL,

	"commit_hash"	TEXT NOT NULL,
	"commit_hash_algo"	TEXT NOT NULL,

	-- A commit should never be part of more than one bundle, so make that the primary key.
	PRIMARY KEY ("commit_hash", "commit_hash_algo")
	FOREIGN KEY ("commit_hash", "commit_hash_algo") REFERENCES "commits" ("hash", "hash_algo") ON DELETE RESTRICT
	FOREIGN KEY ("bundle_hash", "bundle_hash_algo") REFERENCES "bundles" ("hash", "hash_algo") ON DELETE CASCADE
);

CREATE INDEX bundle_commits_hash_idx ON bundle_commits("bundle_hash", "bundle_hash_algo");

CREATE TABLE file_ids (
	"hash"	TEXT NOT NULL,
	"hash_algo"	TEXT NOT NULL,
	"path"	TEXT NOT NULL,
	PRIMARY KEY ("hash", "hash_algo")

	-- ALthough the `UNIQUE` constraint below is not needed internally to this
	-- table, it is required for the `tree_members` table to ensure that two
	-- separate file IDs with the same path value are not added to a single tree
	-- AND that the `("hash", "hash_algo", "path")` tuple in `tree_members`
	-- actually corresponds to a real entry in this table. See the constraints on
	-- the `tree_members` table for more details.
	UNIQUE ("hash", "hash_algo", "path")
);

-- If a given file_id has no parents, it was created "ex nihilo".
CREATE TABLE file_id_parents (
	"file_id_hash"	TEXT NOT NULL,
	"file_id_hash_algo"	TEXT NOT NULL,
	"parent_hash"	TEXT NOT NULL,
	"parent_hash_algo"	TEXT NOT NULL,
	"order"	INTEGER NOT NULL,
	PRIMARY KEY ("file_id_hash", "file_id_hash_algo", "parent_hash", "parent_hash_algo")
	FOREIGN KEY ("file_id_hash", "file_id_hash_algo") REFERENCES "file_ids" ("hash", "hash_algo") ON DELETE RESTRICT
	FOREIGN KEY ("parent_hash", "parent_hash_algo") REFERENCES "file_ids" ("hash", "hash_algo") ON DELETE RESTRICT
);

CREATE TABLE blobs (
	"hash"	TEXT NOT NULL,
	"hash_algo"	TEXT NOT NULL,
	"byte_length"	INTEGER NOT NULL,
	PRIMARY KEY ("hash", "hash_algo")
);

CREATE TABLE unversioned_files (
	"path"	TEXT NOT NULL,
	"blob_hash"	TEXT NOT NULL,
	"blob_hash_algo"	TEXT NOT NULL,
	"created_at" INTEGER DEFAULT CURRENT_TIMESTAMP,

	PRIMARY KEY ("path")
	FOREIGN KEY ("blob_hash", "blob_hash_algo") REFERENCES "blobs" ("hash", "hash_algo") ON DELETE CASCADE
);

CREATE TABLE tree_members (
	"tree_hash"	TEXT NOT NULL,
	"tree_hash_algo"	TEXT NOT NULL,
	"file_id_hash"	TEXT NOT NULL,
	"file_id_hash_algo"	TEXT NOT NULL,
	"path"	TEXT NOT NULL,
	"blob_hash"	TEXT NOT NULL,
	"blob_hash_algo"	TEXT NOT NULL,
	UNIQUE ("tree_hash", "tree_hash_algo", "path")
	PRIMARY KEY ("tree_hash", "tree_hash_algo", "file_id_hash", "file_id_hash_algo")
	FOREIGN KEY ("tree_hash", "tree_hash_algo") REFERENCES "trees" ("hash", "hash_algo") ON DELETE RESTRICT
	FOREIGN KEY ("file_id_hash", "file_id_hash_algo", "path") REFERENCES "file_ids" ("hash", "hash_algo", "path") ON DELETE RESTRICT
	FOREIGN KEY ("blob_hash", "blob_hash_algo") REFERENCES "blobs" ("hash", "hash_algo") ON DELETE RESTRICT
);

CREATE INDEX tmemb_trees_idx ON tree_members("tree_hash", "tree_hash_algo");
CREATE INDEX tmemb_file_ids_idx ON tree_members("file_id_hash", "file_id_hash_algo", "path");
CREATE INDEX tmemb_file_id_hashes_idx ON tree_members("file_id_hash");
CREATE INDEX tmemb_paths_idx ON tree_members("path");
CREATE INDEX tmemb_blobs_idx ON tree_members("blob_hash", "blob_hash_algo");

-- Each blob chunk is compressed individually, so that we can decompress them
-- individually later when streaming them.
CREATE TABLE blob_chunks (
	"blob_hash"	TEXT NOT NULL,
	"blob_hash_algo"	TEXT NOT NULL,

	-- There is no simple constraint to check that start and end byte indices
	-- don't overlap between sibling blob chunks, so this will likely need to be
	-- checked by a more complicated expression in the SQL code at the time of
	-- insertion. Or just have a consistency check that can be run lazily
	-- "offline" after insertion.

	-- The benefit of using start and end indices is that we can change the chunk
	-- size in the configuration and we don't need to rebuild previous entries in
	-- the database for the logic to keep working correctly.
	"start_byte"	INTEGER NOT NULL,
	"end_byte"	INTEGER NOT NULL,
	"compression_algo"	TEXT, -- may be NULL to indicate uncompressed data
	"data"	BLOB NOT NULL,
	PRIMARY KEY ("blob_hash", "blob_hash_algo", "start_byte")
	FOREIGN KEY ("blob_hash", "blob_hash_algo") REFERENCES "blobs" ("hash", "hash_algo") ON DELETE CASCADE
);

CREATE INDEX blb_chnks_blob_idx ON blob_chunks("blob_hash", "blob_hash_algo");
CREATE INDEX blb_chnks_start_byte_idx ON blob_chunks("start_byte");
CREATE INDEX blb_chnks_end_byte_idx ON blob_chunks("end_byte");
