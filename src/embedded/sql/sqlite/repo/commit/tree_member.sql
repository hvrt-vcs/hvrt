-- sqlfluff:dialect:sqlite
INSERT INTO tree_members (
    tree_hash,
    tree_hash_algo,
    name,
    mode
) VALUES ($1, $2, $3, $4);
