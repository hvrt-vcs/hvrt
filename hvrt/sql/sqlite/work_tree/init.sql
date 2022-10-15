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
	PRIMARY KEY ("hash", "hash_algo")
);

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
	FOREIGN KEY ("blob_hash", "blob_hash_algo") REFERENCES "blobs" ("hash", "hash_algo") ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX blb_chnks_blob_idx ON blob_chunks("blob_hash", "blob_hash_algo");
CREATE INDEX blb_chnks_start_byte_idx ON blob_chunks("start_byte");
CREATE INDEX blb_chnks_end_byte_idx ON blob_chunks("end_byte");

CREATE TABLE staged_to_add (
	-- The data for this is just kept in a subdirectory of the worktree config
	-- area. Since the work tree state is ephemeral, it isn't a problem that we
	-- keep it outside of the database for the worktree state. This way, we don't
	-- need to duplicate the logic for blobs and blob chunks that we need in the
	-- main repo database. For simplicity, we can just store blobs as their hash
	-- value, not a shadow path (all we care about is the contents anyway). Added
	-- files can be compared to the file state using timestamp, size, and/or hash
	-- value.
	"path"	TEXT NOT NULL,
	"hash"	TEXT NOT NULL,
	"hash_algo"	TEXT NOT NULL,
	"size" INTEGER NOT NULL,

	-- timestamp
	"added_at" INTEGER NOT NULL,

	PRIMARY KEY ("path")
	FOREIGN KEY ("hash", "hash_algo") REFERENCES "blobs" ("hash", "hash_algo") ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX staged_to_add_blob_idx ON staged_to_add("hash", "hash_algo");

-- File id parents. Can have one, several, or none.
CREATE TABLE staged_to_add_parents (
	"path"	TEXT NOT NULL,
	"fid"	TEXT NOT NULL,
	"fid_algo"	TEXT NOT NULL,
	"order"	INTEGER NOT NULL,
	PRIMARY KEY ("path", "fid", "fid_algo")
	FOREIGN KEY ("path") REFERENCES "staged_to_add" ("path") ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

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
-- trying to be thorough and be add frequently as they get ready to commit, not
-- thinking about the implications of what that means. This might require more
-- thought as we dig into the implementation of this feature.
CREATE TABLE staged_to_remove (
	"fid"	TEXT NOT NULL,
	"fid_algo"	TEXT NOT NULL,
	"path"	TEXT NOT NULL,

	-- An explicit removal is one triggered by `hvrt rm` or `hvrt mv`. If the file
	-- simply disappeared and its removal was recorded by running `hvrt add .` or
	-- commiting, then it will not be considered an explicit removal. This will
	-- effect how mv/cp/rm heuristics are determined.
	"explicit"	BOOLEAN NOT NULL DEFAULT FALSE,
	UNIQUE ("path")
	PRIMARY KEY ("fid", "fid_algo")
);

-- Should only have one entry at any given time.
CREATE TABLE head_commit (
	"hash"	TEXT NOT NULL,
	"hash_algo"	TEXT NOT NULL,
	PRIMARY KEY ("hash", "hash_algo")
);

-- Should a "detached head" state be possible, like in git? Or do all commits
-- need to have at least one tag (usually a branch) in order to be valid?
-- Detached heads cause people lots of pain. However, we don't want to hamstring
-- users. I guess we just generally discourage detached heads, but still allow
-- them for the sake of flexibility and for compatiblity with git.

CREATE TABLE current_tag (
	-- Should only have one entry at any given time?
	"name"	TEXT NOT NULL,
	"is_branch" BOOLEAN NOT NULL,
	PRIMARY KEY ("name")
);

-- Insert default branch when we run this init script.
INSERT INTO current_tag ("name", "is_branch") VALUES ($2, TRUE);
