-- sqlfluff:dialect:sqlite
INSERT INTO commit_parents (
    commit_hash,
    commit_hash_algo,
    parent_hash,
    parent_hash_algo,
    parent_type,
    "order"
) VALUES ($1, $2, $3, $4, $5, $6);
