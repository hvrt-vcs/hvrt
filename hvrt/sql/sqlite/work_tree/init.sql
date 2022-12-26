-- We do not directly hardcode the version value into this init script so that
-- we avoid updating the script with every release of the software.
CREATE TABLE vcs_version (
	"id"	INTEGER,

	"prev"	INTEGER REFERENCES vcs_version("id"),
	-- semantic version
	"version"	TEXT NOT NULL,
	"created_at" INTEGER NOT NULL,
	"modified_at" INTEGER NOT NULL,
	UNIQUE ("version")
	PRIMARY KEY ("id" AUTOINCREMENT)
);

-- Insert the version as a parameter value when we run this init script.
INSERT INTO vcs_version ("id", "version", "created_at", "modified_at")
	VALUES (1, $1, strftime("%s", CURRENT_TIMESTAMP), strftime("%s", CURRENT_TIMESTAMP));

-- XXX: The `blobs` and `blob_chunks` tables should be identical to the same
-- tables in the repo so that when we create commits from the stage, all that we
-- need to do is slurp data directly from here and dump it directly into the
-- repo, no extra processing required.
CREATE TABLE blobs (
	"hash"	TEXT NOT NULL,
	"hash_algo"	TEXT NOT NULL,
	"byte_length"	INTEGER NOT NULL,
	PRIMARY KEY ("hash", "hash_algo") ON CONFLICT IGNORE
);

CREATE TABLE chunks (
	"hash"	TEXT NOT NULL,
	"hash_algo"	TEXT NOT NULL,

	-- Each chunk is compressed individually, so that we can decompress them
	-- individually later when streaming them.
	"compression_algo"	TEXT, -- may be NULL to indicate uncompressed data
	"data"	BLOB NOT NULL,
	PRIMARY KEY ("hash", "hash_algo") ON CONFLICT IGNORE
);

CREATE TABLE blob_chunks (
	"blob_hash"	TEXT NOT NULL,
	"blob_hash_algo"	TEXT NOT NULL,

	"chunk_hash"	TEXT NOT NULL,
	"chunk_hash_algo"	TEXT NOT NULL,

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

	PRIMARY KEY ("blob_hash", "blob_hash_algo", "chunk_hash", "chunk_hash_algo", "start_byte")

	-- When a blob is deleted, its association with any chunks should be severed.
	FOREIGN KEY ("blob_hash", "blob_hash_algo") REFERENCES "blobs" ("hash", "hash_algo") ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED

	-- If connections to existing blobs exist, chunks cannot be deleted. They
	-- should be garbage collected in an offline process or secondary step.
	FOREIGN KEY ("chunk_hash", "chunk_hash_algo") REFERENCES "chunks" ("hash", "hash_algo") ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX blb_chnks_blob_idx ON blob_chunks("blob_hash", "blob_hash_algo");
CREATE INDEX blb_chnks_chunk_idx ON blob_chunks("chunk_hash", "chunk_hash_algo");
CREATE INDEX blb_chnks_start_byte_idx ON blob_chunks("start_byte");
CREATE INDEX blb_chnks_end_byte_idx ON blob_chunks("end_byte");

CREATE TABLE staged_to_add (
	-- How do we differentiate between a "new" file that hasn't been seen before
	-- and a pre-exising file that has been modified? Do we need another table 
	-- or can we use contextual data to tell the difference?
	"path"	TEXT NOT NULL,
	"blob_hash"	TEXT NOT NULL,
	"blob_hash_algo"	TEXT NOT NULL,
	"size" INTEGER NOT NULL,

	-- timestamp to compare to file system timestamp when they differ
	"added_at" INTEGER NOT NULL,

	PRIMARY KEY ("path") ON CONFLICT REPLACE
	FOREIGN KEY ("blob_hash", "blob_hash_algo") REFERENCES "blobs" ("hash", "hash_algo") ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX staged_to_add_blob_idx ON staged_to_add("blob_hash", "blob_hash_algo");

-- File id parents. Can have one, several, or none.
CREATE TABLE staged_to_add_parents (
	"path"	TEXT NOT NULL,
	"fid"	TEXT NOT NULL,
	"fid_algo"	TEXT NOT NULL,
	"order"	INTEGER NOT NULL,
	PRIMARY KEY ("path", "fid", "fid_algo")

	-- Two parent id values cannot inhabit the same location in the order
	UNIQUE ("path", "order")
	FOREIGN KEY ("path") REFERENCES "staged_to_add" ("path") ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE staged_to_remove (
-- It is possible to both add and remove the file at the same path within the
-- same commit. This would indicate that the file is being moved or copied from
-- another file (or being recreated from scratch). However, this situation would
-- only happen if the user explicitly called `hvrt rm <file>; hvrt mv <other>
-- <file>`. Otherwise, the file would be seen as being modified in place when
-- commiting. The tools will only heuristically remove the file from the repo
-- when it doesn't exist at all in the working tree at commit time or if the
-- user called `hvrt add .` and added the missing file to the staging area for
-- the next commit. However, if they removed the file, did `hvrt add .` then
-- added a new file and again did `hvrt add .` it would see it as both a remove
-- and an add and that might not be what the user wants; they could simply be
-- trying to be thorough and be adding frequently as they get ready to commit, not
-- thinking about the implications of what that means. This might require more
-- thought as we dig into the implementation of this feature.

	"fid"	TEXT NOT NULL,
	"fid_algo"	TEXT NOT NULL,
	"path"	TEXT NOT NULL,

	-- An explicit removal is one triggered by `hvrt rm` or `hvrt mv`. If the file
	-- simply disappeared and its removal was recorded by running `hvrt add .` or
	-- commiting, then it will not be considered an explicit removal. This will
	-- effect how mv/cp/rm heuristics are determined.
	"explicit"	BOOLEAN NOT NULL DEFAULT FALSE,
	UNIQUE ("path") ON CONFLICT REPLACE
	PRIMARY KEY ("fid", "fid_algo") ON CONFLICT REPLACE
);

CREATE TABLE head_commit (
-- Should only have one entry at any given time. Ensure this by always
-- attempting to insert with an `id` value of `1`.
	"id"	INTEGER NOT NULL,
	"hash"	TEXT NOT NULL,
	"hash_algo"	TEXT NOT NULL,
	PRIMARY KEY ("id")
);

-- Should a "detached head" state be possible, like in git? Or do all commits
-- need to have at least one tag (usually a branch) in order to be valid?
-- Detached heads cause people lots of pain. However, we don't want to hamstring
-- users. I guess we just generally discourage detached heads, but still allow
-- them for the sake of flexibility and for compatiblity with git.

CREATE TABLE current_tag (
	-- Should only have one entry at any given time? Ensure this by always
	-- attempting to insert with an `id` value of `1`.
	"id"	INTEGER NOT NULL,
	"name"	TEXT NOT NULL,
	"is_branch" BOOLEAN NOT NULL,
	PRIMARY KEY ("id")
);

-- Insert default branch when we run this init script.
INSERT INTO current_tag ("id", "name", "is_branch") VALUES (1, $2, TRUE);
