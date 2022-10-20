INSERT INTO blob_chunks
	("blob_hash", "blob_hash_algo", "start_byte", "end_byte", "compression_algo", "data")
	VALUES ($1, $2, $3, $4, $5, $6);
