INSERT INTO "staged_to_add" ("path", "blob_hash", "blob_hash_algo", "size", "added_at")
	VALUES ($1, $2, $3, $4, strftime("%s", CURRENT_TIMESTAMP));
