-- Insert default branch when we run this init script.
INSERT INTO "current_tag" ("id", "name", "is_branch") VALUES (1, $1, TRUE);

