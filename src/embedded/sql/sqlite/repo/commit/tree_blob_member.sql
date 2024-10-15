-- sqlfluff:dialect:sqlite
INSERT INTO tree_blob_members (
    tree_hash,
    tree_hash_algo,
    name,
    child_hash,
    child_hash_algo
) VALUES ($1, $2, $3, $4, $5);
