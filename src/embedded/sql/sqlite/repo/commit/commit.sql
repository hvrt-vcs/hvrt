-- sqlfluff:dialect:sqlite
INSERT INTO commits (
    hash,
    hash_algo,

    tree_hash,
    tree_hash_algo,

    author,
    author_time,
    author_utc_offset,

    committer,
    committer_time,
    committer_utc_offset,

    message
) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11);
