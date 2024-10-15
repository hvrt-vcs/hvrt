-- sqlfluff:dialect:sqlite
CREATE TABLE vcs_version (
    id INTEGER PRIMARY KEY,

    prev INTEGER REFERENCES vcs_version (id),
    -- semantic version
    version TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    modified_at INTEGER NOT NULL,
    UNIQUE (version)
);

CREATE TABLE tags (
    name TEXT NOT NULL,
    annotation TEXT,

    is_hidden BOOLEAN NOT NULL DEFAULT FALSE,
    is_branch BOOLEAN NOT NULL,
    created_at INTEGER NOT NULL,
    PRIMARY KEY (name)
);

CREATE TABLE default_branch (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    UNIQUE (name),
    FOREIGN KEY (name) REFERENCES tags (
        name
    ) ON DELETE RESTRICT ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE trees (
    -- It is possible
    -- to have a single tree shared between multiple commits.
    -- So long as the tree contents are identical,
    -- they will be hashed to an identical value.
    hash TEXT NOT NULL,
    hash_algo TEXT NOT NULL,
    PRIMARY KEY (hash, hash_algo) ON CONFLICT IGNORE
);

CREATE TABLE commits (
    hash TEXT NOT NULL,
    hash_algo TEXT NOT NULL,

    -- The tree hash and algo cannot be header entries since we need referential
    -- integrity of DB entries. There is only one root tree per commit and each
    -- commit *must* have a tree associated with it.
    tree_hash TEXT NOT NULL,
    tree_hash_algo TEXT NOT NULL,

    -- * author: who authored the commit
    author TEXT NOT NULL,
    -- * author_time: whole seconds since the unix epoch in UTC
    author_time INTEGER NOT NULL,
    -- * author_utc_offset: used to shift "author_time" by the given UTC offset
    -- (mostly for display purposes). Represented in minutes. Between -720 and
    -- 720.
    author_utc_offset INTEGER NOT NULL CHECK (
        author_utc_offset >= -720 AND author_utc_offset <= 720
    ),

    -- * committer: usually same as author
    committer TEXT NOT NULL,
    -- * committer_time: whole seconds since the unix epoch in UTC
    committer_time INTEGER NOT NULL,
    -- * committer_utc_offset: used to shift "committer_time" by the given UTC
    -- offset (mostly for display purposes). Represented in minutes. Between
    -- -720 and 720.
    committer_utc_offset INTEGER NOT NULL CHECK (
        committer_utc_offset >= -720 AND committer_utc_offset <= 720
    ),

    -- * message: Commit message
    message TEXT NOT NULL,

    PRIMARY KEY (hash, hash_algo),
    FOREIGN KEY (tree_hash, tree_hash_algo) REFERENCES trees (
        hash, hash_algo
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE commit_headers (
    commit_hash TEXT NOT NULL,
    commit_hash_algo TEXT NOT NULL,

    -- Some key headers to expect:
    -- * time: whole seconds since the unix epoch in UTC

    -- * tz_offset_hours: used to shift "time" by the given UTC offset (mostly
    -- for display purposes). Between -12 and 12

    -- * tz_offset_minutes: "inherits" the numerical sign of offset hours.
    -- Between 0 and 59.

    -- * message: Commit message
    -- * author: who authored the commit
    -- * committer: usually same as author
    header_key TEXT NOT NULL,
    header_value TEXT NOT NULL,

    -- Other headers for signing and whatnot can easily be added later.

    PRIMARY KEY (commit_hash, commit_hash_algo, header_key),
    FOREIGN KEY (commit_hash, commit_hash_algo) REFERENCES commits (
        hash, hash_algo
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX commit_headers_idx ON commit_headers (header_key, header_value);

CREATE TABLE commit_annotations (
    -- annotations are considered when hashing commits

    id INTEGER PRIMARY KEY,
    parent_commit_hash TEXT NOT NULL,
    parent_commit_hash_algo TEXT NOT NULL,

    reference_commit_hash TEXT NOT NULL,
    reference_commit_hash_algo TEXT NOT NULL,

    -- Can be any key/value pair, not just ones previously specified on commit.
    -- Perhaps this is the best place to put signatures for commits?
    annotation_key TEXT NOT NULL,
    annotation_value TEXT NOT NULL,
    CHECK (
        NOT (
            parent_commit_hash = reference_commit_hash
            AND parent_commit_hash_algo = reference_commit_hash_algo
        )
    ),

    UNIQUE (
        parent_commit_hash,
        parent_commit_hash_algo,
        reference_commit_hash,
        reference_commit_hash_algo,
        annotation_key,
        annotation_value
    ),
    FOREIGN KEY (
        parent_commit_hash, parent_commit_hash_algo
    ) REFERENCES commits (
        hash, hash_algo
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    FOREIGN KEY (
        reference_commit_hash, reference_commit_hash_algo
    ) REFERENCES commits (
        hash, hash_algo
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX annotation_parent_hash_idx ON commit_annotations (
    parent_commit_hash, parent_commit_hash_algo
);
CREATE INDEX annotation_reference_hash_idx ON commit_annotations (
    reference_commit_hash, reference_commit_hash_algo
);

CREATE TABLE commit_tags (
    -- associated branch names/ids are NOT considered when hashing commits
    commit_hash TEXT NOT NULL,
    commit_hash_algo TEXT NOT NULL,
    tag_name TEXT NOT NULL,
    PRIMARY KEY (commit_hash, commit_hash_algo, tag_name),
    FOREIGN KEY (commit_hash, commit_hash_algo) REFERENCES commits (
        hash, hash_algo
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    FOREIGN KEY (tag_name) REFERENCES tags (
        name
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX tag_commits_idx ON commit_tags (commit_hash, commit_hash_algo);
CREATE INDEX commit_tags_idx ON commit_tags (tag_name);

CREATE TABLE commit_parent_types (
    name TEXT NOT NULL,

    PRIMARY KEY (name)
);

INSERT INTO commit_parent_types (name) VALUES ('regular');
INSERT INTO commit_parent_types (name) VALUES ('hidden');
INSERT INTO commit_parent_types (name) VALUES ('cherry_pick');
INSERT INTO commit_parent_types (name) VALUES ('revert');

CREATE TABLE commit_parents (
-- If a given commit has no parents, it is a root commit.
-- If a given commit points to parent that does not exist, it is because of a
-- shallow clone.

    commit_hash TEXT NOT NULL,
    commit_hash_algo TEXT NOT NULL,
    parent_hash TEXT NOT NULL,
    parent_hash_algo TEXT NOT NULL,
    parent_type TEXT NOT NULL,

    -- `order` must be a positive integer greater than zero *and*
    -- the `parent_type` of the first parent must be `regular`.
    "order" INTEGER NOT NULL CHECK (
        "order" >= 1 AND ("order" != 1 OR parent_type = 'regular')
    ),

    PRIMARY KEY (
        commit_hash, commit_hash_algo, parent_hash, parent_hash_algo
    ),

    -- two parents should not be able to be put into the same location in the
    -- order.
    UNIQUE (commit_hash, commit_hash_algo, "order"),
    FOREIGN KEY (commit_hash, commit_hash_algo) REFERENCES commits (
        hash, hash_algo
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    FOREIGN KEY (parent_hash, parent_hash_algo) REFERENCES commits (
        hash, hash_algo
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    FOREIGN KEY (parent_type) REFERENCES commit_parent_types (
        name
    ) ON DELETE RESTRICT ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX commit_parents_commit_id_idx ON commit_parents (
    commit_hash, commit_hash_algo
);
CREATE INDEX commit_parents_parent_id_idx ON commit_parents (
    parent_hash, parent_hash_algo
);

CREATE TABLE blobs (
    hash TEXT NOT NULL,
    hash_algo TEXT NOT NULL,
    byte_length INTEGER NOT NULL,
    PRIMARY KEY (hash, hash_algo) ON CONFLICT IGNORE
);

-- XXX: fossil has something similar.
-- My thinking was that this would be useful for hosting static sites,
-- but this may be beyond the scope of the project.
-- There are plenty of places and ways to host static files;
-- it doesn't necessarily need to be in the repo DB.
CREATE TABLE unversioned_files (
    path TEXT NOT NULL,
    blob_hash TEXT NOT NULL,
    blob_hash_algo TEXT NOT NULL,
    created_at INTEGER DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (path),
    FOREIGN KEY (blob_hash, blob_hash_algo) REFERENCES blobs (
        hash, hash_algo
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE tree_members (
    tree_hash TEXT NOT NULL,
    tree_hash_algo TEXT NOT NULL,
    name TEXT NOT NULL,

    -- TODO: use integers instead
    -- because they are smaller and faster to compare

    -- octal mode meanings from this link:
    -- https://stackoverflow.com/a/8347325/1733321
    --
    --   0100­000­000000000 (040000): Directory
    --
    --   1000­000­110100100 (100644): Regular non-executable file
    --
    --   1000­000­110110100 (100664):
    --      Regular non-executable group-writeable file (unused)
    --
    --   1000­000­111101101 (100755): Regular executable file
    --
    --   1010­000­000000000 (120000): Symbolic link
    --
    --   1110­000­000000000 (160000): Gitlink
    mode TEXT NOT NULL CHECK (
        mode IN ('040000', '100644', '100664', '100755', '120000', '160000')
    ),
    UNIQUE (tree_hash, tree_hash_algo, name),
    PRIMARY KEY (tree_hash, tree_hash_algo, name),
    FOREIGN KEY (tree_hash, tree_hash_algo) REFERENCES trees (
        hash, hash_algo
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX tmemb_trees_idx ON tree_members (
    tree_hash, tree_hash_algo
);
CREATE INDEX tmemb_names_idx ON tree_members (name);

CREATE TABLE tree_tree_members (
    tree_hash TEXT NOT NULL,
    tree_hash_algo TEXT NOT NULL,
    name TEXT NOT NULL,
    child_hash TEXT NOT NULL,
    child_hash_algo TEXT NOT NULL,
    UNIQUE (tree_hash, tree_hash_algo, name),
    PRIMARY KEY (
        tree_hash, tree_hash_algo, child_hash, child_hash_algo
    ),
    FOREIGN KEY (tree_hash, tree_hash_algo) REFERENCES trees (
        hash, hash_algo
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    FOREIGN KEY (child_hash, child_hash_algo) REFERENCES trees (
        hash, hash_algo
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    CHECK (NOT (tree_hash = child_hash AND tree_hash_algo = child_hash_algo))
);

CREATE INDEX ttmemb_trees_idx ON tree_tree_members (
    tree_hash, tree_hash_algo
);
CREATE INDEX ttmemb_names_idx ON tree_tree_members (name);
CREATE INDEX ttmemb_blobs_idx ON tree_tree_members (
    child_hash, child_hash_algo
);

CREATE TABLE tree_blob_members (
    tree_hash TEXT NOT NULL,
    tree_hash_algo TEXT NOT NULL,
    name TEXT NOT NULL,
    child_hash TEXT NOT NULL,
    child_hash_algo TEXT NOT NULL,
    UNIQUE (tree_hash, tree_hash_algo, name),
    PRIMARY KEY (
        tree_hash, tree_hash_algo, child_hash, child_hash_algo
    ),
    FOREIGN KEY (tree_hash, tree_hash_algo) REFERENCES trees (
        hash, hash_algo
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    FOREIGN KEY (child_hash, child_hash_algo) REFERENCES blobs (
        hash, hash_algo
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX tbmemb_trees_idx ON tree_blob_members (
    tree_hash, tree_hash_algo
);
CREATE INDEX tbmemb_names_idx ON tree_blob_members (name);
CREATE INDEX tbmemb_blobs_idx ON tree_blob_members (
    child_hash, child_hash_algo
);

-- FIXME: This won't work when a tree is referencing itself. i.e. `.` (period)
CREATE TABLE tree_copy_sources (
    dst_tree_hash TEXT NOT NULL,
    dst_tree_hash_algo TEXT NOT NULL,
    dst_name TEXT NOT NULL,
    src_tree_hash TEXT NOT NULL,
    src_tree_hash_algo TEXT NOT NULL,
    src_name TEXT NOT NULL,
    "order" INTEGER NOT NULL CHECK ("order" >= 1),
    PRIMARY KEY (
        dst_tree_hash,
        dst_tree_hash_algo,
        dst_name,
        src_tree_hash,
        src_tree_hash_algo,
        src_name
    ),

    -- two sources should not be able to be put into the same location
    -- in the order.
    UNIQUE (dst_tree_hash, dst_tree_hash_algo, "order"),
    FOREIGN KEY (
        dst_tree_hash, dst_tree_hash_algo, dst_name
    ) REFERENCES tree_members (
        hash, hash_algo, name
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    FOREIGN KEY (
        src_tree_hash, src_tree_hash_algo, src_name
    ) REFERENCES tree_members (
        hash, hash_algo, name
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE chunks (
    hash TEXT NOT NULL,
    hash_algo TEXT NOT NULL,

    -- Each chunk is compressed individually, so that we can decompress them
    -- individually later when streaming them.
    -- may be string value "none" to indicate uncompressed data
    compression_algo TEXT NOT NULL,
    data BLOB NOT NULL,
    PRIMARY KEY (hash, hash_algo) ON CONFLICT IGNORE
);

CREATE TABLE blob_chunks (
    blob_hash TEXT NOT NULL,
    blob_hash_algo TEXT NOT NULL,

    chunk_hash TEXT NOT NULL,
    chunk_hash_algo TEXT NOT NULL,

    -- There is no simple constraint to check that start and end byte indices
    -- don't overlap between sibling blob chunks, so this will likely need to
    -- be checked by a more complicated expression in the SQL code at the time
    -- of insertion. Or just have a consistency check that can be run lazily
    -- "offline" after insertion.

    -- The benefit of using start and end indices is that we can change the
    -- chunk size in the configuration and we don't need to rebuild previous
    -- entries in the database for the logic to keep working correctly.
    start_byte INTEGER NOT NULL,
    end_byte INTEGER NOT NULL,

    PRIMARY KEY (
        blob_hash, blob_hash_algo, chunk_hash, chunk_hash_algo, start_byte
    ) ON CONFLICT IGNORE,

    -- When a blob is deleted,
    -- its association with any chunks should be severed.
    FOREIGN KEY (blob_hash, blob_hash_algo) REFERENCES blobs (
        hash, hash_algo
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,

    -- If connections to existing blobs exist, chunks cannot be deleted. They
    -- should be garbage collected in an offline process or secondary step.
    FOREIGN KEY (chunk_hash, chunk_hash_algo) REFERENCES chunks (
        hash, hash_algo
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX blb_chnks_blob_idx ON blob_chunks (blob_hash, blob_hash_algo);
CREATE INDEX blb_chnks_chunk_idx ON blob_chunks (
    chunk_hash, chunk_hash_algo
);
CREATE INDEX blb_chnks_start_byte_idx ON blob_chunks (start_byte);
CREATE INDEX blb_chnks_end_byte_idx ON blob_chunks (end_byte);
