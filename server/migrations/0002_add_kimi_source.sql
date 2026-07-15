CREATE TABLE token_usage_with_kimi (
    user_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    usage_day TEXT NOT NULL,
    usage_id TEXT NOT NULL,
    source TEXT NOT NULL CHECK (source IN ('opencode', 'zcode', 'codex', 'claude', 'kimi')),
    provider TEXT NOT NULL,
    model TEXT NOT NULL,
    input_tokens INTEGER NOT NULL CHECK (input_tokens >= 0),
    cached_input_tokens INTEGER NOT NULL CHECK (cached_input_tokens >= 0),
    cache_write_tokens INTEGER NOT NULL CHECK (cache_write_tokens >= 0),
    output_tokens INTEGER NOT NULL CHECK (output_tokens >= 0),
    reasoning_tokens INTEGER NOT NULL CHECK (reasoning_tokens >= 0),
    revision INTEGER NOT NULL CHECK (revision > 0),
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, device_id, usage_day, usage_id),
    FOREIGN KEY (user_id, device_id, usage_day)
        REFERENCES device_day_revisions(user_id, device_id, usage_day) ON DELETE CASCADE
) WITHOUT ROWID;

INSERT INTO token_usage_with_kimi(
    user_id, device_id, usage_day, usage_id, source, provider, model,
    input_tokens, cached_input_tokens, cache_write_tokens, output_tokens,
    reasoning_tokens, revision, updated_at
)
SELECT
    user_id, device_id, usage_day, usage_id, source, provider, model,
    input_tokens, cached_input_tokens, cache_write_tokens, output_tokens,
    reasoning_tokens, revision, updated_at
FROM token_usage;

DROP TABLE token_usage;
ALTER TABLE token_usage_with_kimi RENAME TO token_usage;

CREATE INDEX token_usage_user_day_idx ON token_usage(user_id, usage_day);
CREATE INDEX token_usage_user_device_day_idx ON token_usage(user_id, device_id, usage_day);
