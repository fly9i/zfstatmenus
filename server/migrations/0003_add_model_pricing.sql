-- 远端模型定价：供同步面板展示与编辑，按用户隔离，(user_id, provider, model) 唯一。
-- provider/model 统一以小写存储，便于与用量数据做大小写无关匹配。
CREATE TABLE model_pricing (
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider TEXT NOT NULL,
    model TEXT NOT NULL,
    currency TEXT NOT NULL DEFAULT 'usd' CHECK (currency IN ('usd', 'cny')),
    input_per_mtok REAL NOT NULL DEFAULT 0 CHECK (input_per_mtok >= 0),
    cached_input_per_mtok REAL NOT NULL DEFAULT 0 CHECK (cached_input_per_mtok >= 0),
    cache_write_per_mtok REAL NOT NULL DEFAULT 0 CHECK (cache_write_per_mtok >= 0),
    output_per_mtok REAL NOT NULL DEFAULT 0 CHECK (output_per_mtok >= 0),
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, provider, model)
) WITHOUT ROWID;

CREATE INDEX model_pricing_user_idx ON model_pricing(user_id);
