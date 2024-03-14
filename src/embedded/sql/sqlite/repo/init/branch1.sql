-- Insert default branch when we run this init script.
INSERT INTO "tags" ("name", "is_branch", "created_at")
	VALUES ($1, TRUE, strftime("%s", CURRENT_TIMESTAMP));

