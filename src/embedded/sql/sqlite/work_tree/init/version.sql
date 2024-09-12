-- Insert the version as a parameter value when we run this init script.
INSERT INTO vcs_version (id, version, created_at, modified_at)
VALUES (
    1, $1, strftime('%s', current_timestamp), strftime('%s', current_timestamp)
);
