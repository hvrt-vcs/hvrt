CREATE TABLE "tags" (
	"id"	INTEGER,
	"name"	TEXT NOT NULL,
	"annotation"	TEXT,
	"is_hidden" BOOLEAN NOT NULL DEFAULT FALSE,
	"is_branch" BOOLEAN NOT NULL DEFAULT FALSE,
	"created_at" TEXT DEFAULT CURRENT_TIMESTAMP,
	PRIMARY KEY("id" AUTOINCREMENT)
)

CREATE TABLE "commits" (
	"id"	INTEGER,
	"hash_algo"	TEXT NOT NULL,
	"hash"	TEXT NOT NULL,
	"time"	TEXT NOT NULL, -- ISO8601 (should "local" time be allowed?)
	"message"	TEXT NOT NULL,
	"committer"	TEXT NOT NULL,
	"tree_id"	INTEGER NOT NULL,
	UNIQUE("hash_algo", "hash")
	PRIMARY KEY("id" AUTOINCREMENT)
	FOREIGN KEY ("branch_id") REFERENCES "branches" ("id") ON DELETE RESTRICT
)

CREATE TABLE "commit_authors" (
	"id"	INTEGER,
	"commit_id"	INTEGER NOT NULL,
	"author"	TEXT NOT NULL,
	"order"	INTEGER NOT NULL,
	UNIQUE("hash_algo", "hash")
	PRIMARY KEY("id" AUTOINCREMENT)
	FOREIGN KEY ("commit_id") REFERENCES "commits" ("id") ON DELETE RESTRICT
)

CREATE TABLE "commit_tags" (
	"id"	INTEGER,
	"commit_id"	INTEGER NOT NULL, -- branch names/ids are NOT considered when hashing commits
	"tag_id"	INTEGER NOT NULL,
	UNIQUE("commit_id", "tag_id")
	PRIMARY KEY("id" AUTOINCREMENT)
	FOREIGN KEY ("commit_id") REFERENCES "commits" ("id") ON DELETE RESTRICT
	FOREIGN KEY ("tag_id") REFERENCES "tags" ("id") ON DELETE CASCADE
)

CREATE INDEX tag_commits_index ON commit_tags("commit_id");
CREATE INDEX commit_tags_index ON commit_tags("tag_id");

CREATE TABLE "commit_parents" (
	"id"	INTEGER,
	"commit_id"	INTEGER NOT NULL,
	"parent_id"	INTEGER NOT NULL,
	"parent_type"	TEXT CHECK("merge_type" IN ('regular', 'merge', 'cherry_pick', 'replay', 'reorder')) NOT NULL DEFAULT 'regular',
	"order"	INTEGER NOT NULL,
	UNIQUE("commit_id", "parent_id")
	PRIMARY KEY("id" AUTOINCREMENT)
	FOREIGN KEY ("commit_id") REFERENCES "commits" ("id") ON DELETE RESTRICT
	FOREIGN KEY ("parent_id") REFERENCES "commits" ("id") ON DELETE RESTRICT
)

CREATE INDEX commit_parents_commit_id ON commit_parents("commit_id");
CREATE INDEX commit_parents_parent_id ON commit_parents("parent_id");

CREATE TABLE "bundles" (
	"id"	INTEGER,
	"name"	TEXT NOT NULL,
	"message"	TEXT,
	"created_at" TEXT DEFAULT CURRENT_TIMESTAMP,
	"modified_at" TEXT DEFAULT CURRENT_TIMESTAMP,
	UNIQUE("name")
	PRIMARY KEY("id" AUTOINCREMENT)
)

CREATE TABLE "bundle_commits" (
	"id"	INTEGER,
	"bundle_id"	INTEGER NOT NULL,
	"commit_id"	INTEGER NOT NULL,
	"created_at" TEXT DEFAULT CURRENT_TIMESTAMP,
	PRIMARY KEY("id" AUTOINCREMENT)
	UNIQUE("commit_id") -- creates index automatically
	FOREIGN KEY ("bundle_id") REFERENCES "bundles" ("id") ON DELETE CASCADE
	FOREIGN KEY ("commit_id") REFERENCES "commits" ("id") ON DELETE RESTRICT
)

CREATE INDEX bundle_commits_bundle_id ON bundle_commits("bundle_id");

CREATE TABLE "trees" (
	"id"	INTEGER,
	"hash_algo"	TEXT NOT NULL,
	"hash"	TEXT NOT NULL,
	UNIQUE("hash_algo", "hash")
	PRIMARY KEY("id" AUTOINCREMENT)
)

CREATE TABLE "file_ids" (
	"id"	INTEGER,
	"hash_algo"	TEXT NOT NULL,
	"hash"	TEXT NOT NULL,
	"path"	TEXT NOT NULL,
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

-- If a given file_id has no parents, it was created "ex nihilo".
CREATE TABLE "file_id_parents" (
	"id"	INTEGER,
	"file_id"	INTEGER NOT NULL,
	"parent"	INTEGER NOT NULL,
	"order"	INTEGER NOT NULL,
	UNIQUE("fid", "parent")
	PRIMARY KEY("id" AUTOINCREMENT)
	FOREIGN KEY ("file_id") REFERENCES "file_ids" ("id")
	FOREIGN KEY ("parent") REFERENCES "file_ids" ("id")
)

CREATE TABLE "blobs" (
	"id"	INTEGER,
	"hash_algo"	TEXT NOT NULL,
	"hash"	TEXT NOT NULL,
	"byte_length"	INTEGER NOT NULL,
	UNIQUE("hash_algo", "hash")
	PRIMARY KEY("id" AUTOINCREMENT)
)

-- Each blob chunk is compressed individually, so that we can decompress them
-- individually later.
CREATE TABLE "blob_chunks" (
	"id"	INTEGER,
	"blob_id"	INTEGER NOT NULL,
	"start_byte"	INTEGER NOT NULL,
	"end_byte"	INTEGER NOT NULL,
	"compression_algo"	TEXT,
	"data"	BLOB NOT NULL,
	PRIMARY KEY("id" AUTOINCREMENT)
	FOREIGN KEY ("blob_id") REFERENCES "blobs" ("id")
)

CREATE INDEX blob_chunks_blob_id_index ON blob_chunks("blob_id");
CREATE INDEX blob_chunks_start_byte_index ON blob_chunks("start_byte");
CREATE INDEX blob_chunks_end_byte_index ON blob_chunks("end_byte");
