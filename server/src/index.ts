import { timingSafeEqual } from "node:crypto";
import { DASHBOARD_HTML } from "./dashboard";
import { builtinPricing, costForTokens, type ModelPricing, type TokenSums } from "./pricing";

const MAX_REQUEST_BYTES = 1_000_000;
const MAX_SYNC_DAYS = 31;
const MAX_USAGES_PER_DAY = 200;
const MAX_SNAPSHOT_ROWS = 20_000;
const MAX_STATS_ROWS = 20_000;
const MAX_STATS_MODELS = 500;
const MAX_PRICE_PER_MTOK = 1_000_000;
const ALLOWED_SOURCES = new Set(["opencode", "zcode", "codex", "claude", "kimi"]);
const ALLOWED_CURRENCIES = new Set(["usd", "cny"]);

type JSONValue = string | number | boolean | null | JSONValue[] | { [key: string]: JSONValue };

interface Principal {
  userId: string;
  displayName: string;
  tokenId: string;
  lastUsedAt: string | null;
}

interface TokenRow {
  token_id: string;
  user_id: string;
  display_name: string;
  token_hash: string;
  last_used_at: string | null;
}

interface DeviceInput {
  id: string;
  name: string;
  appVersion: string;
}

interface UsageInput {
  source: string;
  provider: string;
  model: string;
  inputTokens: number;
  cachedInputTokens: number;
  cacheWriteTokens: number;
  outputTokens: number;
  reasoningTokens: number;
}

interface DayInput {
  day: string;
  revision: number;
  usages: UsageInput[];
}

interface SyncInput {
  schemaVersion: 1;
  device: DeviceInput;
  days: DayInput[];
}

interface SnapshotRow {
  device_id: string;
  device_name: string;
  usage_day: string;
  source: string;
  provider: string;
  model: string;
  input_tokens: number;
  cached_input_tokens: number;
  cache_write_tokens: number;
  output_tokens: number;
  reasoning_tokens: number;
}

class HTTPError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    const startedAt = Date.now();

    try {
      if (request.method === "GET" && url.pathname === "/v1/health") {
        return json({ ok: true, serverTime: new Date().toISOString() });
      }

      if (request.method === "GET" && (url.pathname === "/" || url.pathname === "/dashboard")) {
        return html(DASHBOARD_HTML);
      }

      const principal = await authenticate(request, env);
      if (shouldUpdateLastUsed(principal.lastUsedAt)) {
        ctx.waitUntil(
          env.DB.prepare("UPDATE access_tokens SET last_used_at = CURRENT_TIMESTAMP WHERE id = ?")
            .bind(principal.tokenId)
            .run()
            .then(() => undefined),
        );
      }

      let response: Response;
      if (request.method === "GET" && url.pathname === "/v1/me") {
        response = await handleMe(env, principal);
      } else if (request.method === "POST" && url.pathname === "/v1/sync") {
        response = await handleSync(request, env, principal);
      } else if (request.method === "GET" && url.pathname === "/v1/snapshot") {
        response = await handleSnapshot(url, env, principal);
      } else if (request.method === "GET" && url.pathname === "/v1/stats") {
        response = await handleStats(url, env, principal);
      } else if (request.method === "GET" && url.pathname === "/v1/pricing") {
        response = await handlePricingList(env, principal);
      } else if (request.method === "PUT" && url.pathname === "/v1/pricing") {
        response = await handlePricingUpsert(request, env, principal);
      } else if (request.method === "DELETE" && url.pathname === "/v1/pricing") {
        response = await handlePricingDelete(url, env, principal);
      } else {
        throw new HTTPError(404, "not_found", "接口不存在");
      }

      console.log(JSON.stringify({
        message: "request_completed",
        method: request.method,
        path: url.pathname,
        status: response.status,
        userId: principal.userId,
        durationMs: Date.now() - startedAt,
      }));
      return response;
    } catch (error) {
      const handled = toErrorResponse(error);
      const log = {
        message: "request_failed",
        method: request.method,
        path: url.pathname,
        status: handled.status,
        error: error instanceof Error ? error.message : String(error),
        durationMs: Date.now() - startedAt,
      };
      if (handled.status >= 500) console.error(JSON.stringify(log));
      else console.log(JSON.stringify(log));
      return handled;
    }
  },
} satisfies ExportedHandler<Env>;

async function authenticate(request: Request, env: Env): Promise<Principal> {
  const authorization = request.headers.get("Authorization") ?? "";
  const match = /^Bearer\s+(zfsm_([A-Za-z0-9_-]{12})_[A-Za-z0-9_-]{40,})$/i.exec(authorization);
  if (!match?.[1] || !match[2]) {
    throw new HTTPError(401, "unauthorized", "访问 Token 无效");
  }

  const providedToken = match[1];
  const prefix = match[2];
  const row = await env.DB.prepare(
    `SELECT t.id AS token_id, t.user_id, u.display_name, t.token_hash, t.last_used_at
       FROM access_tokens t
       JOIN users u ON u.id = t.user_id
      WHERE t.token_prefix = ?
        AND t.revoked_at IS NULL
        AND (t.expires_at IS NULL OR t.expires_at > CURRENT_TIMESTAMP)
        AND u.active = 1`,
  ).bind(prefix).first<TokenRow>();

  if (!row) throw new HTTPError(401, "unauthorized", "访问 Token 无效");

  const providedHash = await sha256Bytes(providedToken);
  const storedHash = hexToBytes(row.token_hash);
  if (storedHash.length !== providedHash.length || !timingSafeEqual(providedHash, storedHash)) {
    throw new HTTPError(401, "unauthorized", "访问 Token 无效");
  }

  return {
    userId: row.user_id,
    displayName: row.display_name,
    tokenId: row.token_id,
    lastUsedAt: row.last_used_at,
  };
}

async function handleMe(env: Env, principal: Principal): Promise<Response> {
  const result = await env.DB.prepare(
    `SELECT id, name, app_version AS appVersion, last_seen_at AS lastSeenAt
       FROM devices
      WHERE user_id = ?
      ORDER BY last_seen_at DESC
      LIMIT 100`,
  ).bind(principal.userId).all();

  return json({
    user: { id: principal.userId, displayName: principal.displayName },
    devices: result.results,
    serverTime: new Date().toISOString(),
  });
}

async function handleSync(request: Request, env: Env, principal: Principal): Promise<Response> {
  const input = validateSyncInput(await readJSONWithLimit(request, MAX_REQUEST_BYTES));

  await env.DB.prepare(
    `INSERT INTO devices(user_id, id, name, app_version, last_seen_at)
     VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
     ON CONFLICT(user_id, id) DO UPDATE SET
       name = excluded.name,
       app_version = excluded.app_version,
       last_seen_at = CURRENT_TIMESTAMP`,
  ).bind(principal.userId, input.device.id, input.device.name, input.device.appVersion).run();

  const accepted: Array<{ day: string; revision: number }> = [];
  for (const day of input.days) {
    const statements: D1PreparedStatement[] = [
      env.DB.prepare(
        `INSERT INTO device_day_revisions(user_id, device_id, usage_day, revision, updated_at)
         VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
         ON CONFLICT(user_id, device_id, usage_day) DO UPDATE SET
           revision = excluded.revision,
           updated_at = CURRENT_TIMESTAMP
         WHERE excluded.revision > device_day_revisions.revision`,
      ).bind(principal.userId, input.device.id, day.day, day.revision),
      env.DB.prepare(
        `DELETE FROM token_usage
          WHERE user_id = ? AND device_id = ? AND usage_day = ? AND revision < ?
            AND EXISTS (
              SELECT 1 FROM device_day_revisions
               WHERE user_id = ? AND device_id = ? AND usage_day = ? AND revision = ?
            )`,
      ).bind(
        principal.userId, input.device.id, day.day, day.revision,
        principal.userId, input.device.id, day.day, day.revision,
      ),
    ];

    for (const usage of day.usages) {
      statements.push(env.DB.prepare(
        `INSERT INTO token_usage(
           user_id, device_id, usage_day, usage_id, source, provider, model,
           input_tokens, cached_input_tokens, cache_write_tokens,
           output_tokens, reasoning_tokens, revision, updated_at
         )
         SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP
          WHERE EXISTS (
            SELECT 1 FROM device_day_revisions
             WHERE user_id = ? AND device_id = ? AND usage_day = ? AND revision = ?
          )
         ON CONFLICT(user_id, device_id, usage_day, usage_id) DO UPDATE SET
           source = excluded.source,
           provider = excluded.provider,
           model = excluded.model,
           input_tokens = excluded.input_tokens,
           cached_input_tokens = excluded.cached_input_tokens,
           cache_write_tokens = excluded.cache_write_tokens,
           output_tokens = excluded.output_tokens,
           reasoning_tokens = excluded.reasoning_tokens,
           revision = excluded.revision,
           updated_at = CURRENT_TIMESTAMP
         WHERE excluded.revision > token_usage.revision`,
      ).bind(
        principal.userId,
        input.device.id,
        day.day,
        usageId(usage),
        usage.source,
        usage.provider,
        usage.model,
        usage.inputTokens,
        usage.cachedInputTokens,
        usage.cacheWriteTokens,
        usage.outputTokens,
        usage.reasoningTokens,
        day.revision,
        principal.userId,
        input.device.id,
        day.day,
        day.revision,
      ));
    }

    await env.DB.batch(statements);
    const currentRevision = await env.DB.prepare(
      "SELECT revision FROM device_day_revisions WHERE user_id = ? AND device_id = ? AND usage_day = ?",
    ).bind(principal.userId, input.device.id, day.day).first<number>("revision");
    accepted.push({ day: day.day, revision: currentRevision ?? day.revision });
  }

  return json({ accepted, serverTime: new Date().toISOString() });
}

async function handleSnapshot(url: URL, env: Env, principal: Principal): Promise<Response> {
  const from = requireDay(url.searchParams.get("from"), "from");
  const to = requireDay(url.searchParams.get("to"), "to");
  const excludeDeviceId = requireString(url.searchParams.get("excludeDeviceId"), "excludeDeviceId", 64);
  const range = dayDifference(from, to);
  if (range < 0 || range > 365) {
    throw new HTTPError(400, "invalid_date_range", "日期范围必须为 1～366 天");
  }

  const result = await env.DB.prepare(
    `SELECT t.device_id, d.name AS device_name, t.usage_day, t.source, t.provider, t.model,
            t.input_tokens, t.cached_input_tokens, t.cache_write_tokens,
            t.output_tokens, t.reasoning_tokens
       FROM token_usage t
       JOIN devices d ON d.user_id = t.user_id AND d.id = t.device_id
      WHERE t.user_id = ?
        AND t.usage_day BETWEEN ? AND ?
        AND t.device_id <> ?
      ORDER BY t.usage_day, t.device_id, t.source, t.provider, t.model
      LIMIT ?`,
  ).bind(principal.userId, from, to, excludeDeviceId, MAX_SNAPSHOT_ROWS + 1).all<SnapshotRow>();

  if (result.results.length > MAX_SNAPSHOT_ROWS) {
    throw new HTTPError(413, "snapshot_too_large", "远程数据过多，请缩小日期范围");
  }

  return json({
    rows: result.results.map((row) => ({
      deviceId: row.device_id,
      deviceName: row.device_name,
      day: row.usage_day,
      source: row.source,
      provider: row.provider,
      model: row.model,
      inputTokens: row.input_tokens,
      cachedInputTokens: row.cached_input_tokens,
      cacheWriteTokens: row.cache_write_tokens,
      outputTokens: row.output_tokens,
      reasoningTokens: row.reasoning_tokens,
    })),
    serverTime: new Date().toISOString(),
  });
}

const TOKEN_SUM_COLUMNS = `SUM(t.input_tokens) AS inputTokens,
       SUM(t.cached_input_tokens) AS cachedInputTokens,
       SUM(t.cache_write_tokens) AS cacheWriteTokens,
       SUM(t.output_tokens) AS outputTokens,
       SUM(t.reasoning_tokens) AS reasoningTokens`;

type StatsGranularRow = TokenSums & {
  day: string;
  source: string;
  deviceId: string;
  deviceName: string;
  provider: string;
  model: string;
};

type UserPricingRow = {
  provider: string;
  model: string;
  currency: string;
  inputPerMtok: number;
  cachedInputPerMtok: number;
  cacheWritePerMtok: number;
  outputPerMtok: number;
};

type CostAggregate = TokenSums & {
  usdCost: number;
  cnyCost: number;
};

type ModelAggregate = CostAggregate & {
  provider: string;
  model: string;
  priced: number;
  priceSource: "user" | "builtin" | null;
  price: ModelPricing | null;
};

function emptyAggregate(): CostAggregate {
  return {
    inputTokens: 0, cachedInputTokens: 0, cacheWriteTokens: 0,
    outputTokens: 0, reasoningTokens: 0, usdCost: 0, cnyCost: 0,
  };
}

function aggregateTokens(row: TokenSums): number {
  return row.inputTokens + row.cachedInputTokens + row.cacheWriteTokens
    + row.outputTokens + row.reasoningTokens;
}

// 定价优先级：用户自定义（model_pricing 表，精确匹配）> 内置目录（与客户端同步的规则匹配）。
function resolvePricing(
  provider: string,
  model: string,
  userPricing: ReadonlyMap<string, ModelPricing>,
): { pricing: ModelPricing; source: "user" | "builtin" } | null {
  const user = userPricing.get(`${provider.toLowerCase()}|${model.toLowerCase()}`);
  if (user) return { pricing: user, source: "user" };
  const builtin = builtinPricing(provider, model);
  if (builtin) return { pricing: builtin, source: "builtin" };
  return null;
}

function splitCost(pricing: ModelPricing | null, row: TokenSums): { usd: number; cny: number } {
  if (!pricing) return { usd: 0, cny: 0 };
  const cost = costForTokens(pricing, row);
  return pricing.currency === "cny" ? { usd: 0, cny: cost } : { usd: cost, cny: 0 };
}

function accumulate(target: CostAggregate, row: TokenSums, cost: { usd: number; cny: number }): void {
  target.inputTokens += row.inputTokens;
  target.cachedInputTokens += row.cachedInputTokens;
  target.cacheWriteTokens += row.cacheWriteTokens;
  target.outputTokens += row.outputTokens;
  target.reasoningTokens += row.reasoningTokens;
  target.usdCost += cost.usd;
  target.cnyCost += cost.cny;
}

// 按 (日期, 来源, 设备, 模型) 粒度查询后在 JS 内聚合：内置目录是规则匹配（前缀/包含），
// 无法表达为 model_pricing 的精确 JOIN，统一在这里套用 用户定价 > 内置定价 的优先级。
async function handleStats(url: URL, env: Env, principal: Principal): Promise<Response> {
  const { from, to } = statsRange(url);

  const [granular, pricingRows] = await Promise.all([
    env.DB.prepare(
      `SELECT t.usage_day AS day, t.source AS source, t.device_id AS deviceId, d.name AS deviceName,
              t.provider AS provider, t.model AS model, ${TOKEN_SUM_COLUMNS}
         FROM token_usage t
         JOIN devices d ON d.user_id = t.user_id AND d.id = t.device_id
        WHERE t.user_id = ? AND t.usage_day BETWEEN ? AND ?
        GROUP BY t.usage_day, t.source, t.device_id, t.provider, t.model
        LIMIT ?`,
    ).bind(principal.userId, from, to, MAX_STATS_ROWS + 1).all<StatsGranularRow>(),
    env.DB.prepare(
      `SELECT provider, model, currency,
              input_per_mtok AS inputPerMtok, cached_input_per_mtok AS cachedInputPerMtok,
              cache_write_per_mtok AS cacheWritePerMtok, output_per_mtok AS outputPerMtok
         FROM model_pricing WHERE user_id = ?`,
    ).bind(principal.userId).all<UserPricingRow>(),
  ]);

  if (granular.results.length > MAX_STATS_ROWS) {
    throw new HTTPError(413, "stats_too_large", "统计数据过多，请缩小日期范围");
  }

  const userPricing = new Map<string, ModelPricing>();
  for (const row of pricingRows.results) {
    userPricing.set(`${row.provider}|${row.model}`, {
      currency: row.currency === "cny" ? "cny" : "usd",
      inputPerMtok: row.inputPerMtok,
      cachedInputPerMtok: row.cachedInputPerMtok,
      cacheWritePerMtok: row.cacheWritePerMtok,
      outputPerMtok: row.outputPerMtok,
    });
  }

  const days = new Map<string, CostAggregate>();
  const models = new Map<string, ModelAggregate>();
  const sources = new Map<string, CostAggregate>();
  const devices = new Map<string, CostAggregate & { deviceId: string; deviceName: string }>();

  for (const row of granular.results) {
    const resolved = resolvePricing(row.provider, row.model, userPricing);
    const cost = splitCost(resolved?.pricing ?? null, row);

    const day = days.get(row.day) ?? emptyAggregate();
    accumulate(day, row, cost);
    days.set(row.day, day);

    const modelKey = `${row.provider} ${row.model}`;
    const model = models.get(modelKey) ?? {
      ...emptyAggregate(),
      provider: row.provider,
      model: row.model,
      priced: resolved ? 1 : 0,
      priceSource: resolved?.source ?? null,
      price: resolved?.pricing ?? null,
    };
    accumulate(model, row, cost);
    models.set(modelKey, model);

    const source = sources.get(row.source) ?? emptyAggregate();
    accumulate(source, row, cost);
    sources.set(row.source, source);

    const device = devices.get(row.deviceId) ?? {
      ...emptyAggregate(), deviceId: row.deviceId, deviceName: row.deviceName,
    };
    accumulate(device, row, cost);
    devices.set(row.deviceId, device);
  }

  const byTotalDesc = (a: CostAggregate, b: CostAggregate) => aggregateTokens(b) - aggregateTokens(a);

  return json({
    from,
    to,
    days: [...days.entries()].sort(([a], [b]) => (a < b ? -1 : 1)).map(([day, aggregate]) => ({ day, ...aggregate })),
    models: [...models.values()].sort(byTotalDesc).slice(0, MAX_STATS_MODELS),
    sources: [...sources.entries()].sort(([, a], [, b]) => byTotalDesc(a, b)).map(([source, aggregate]) => ({ source, ...aggregate })),
    devices: [...devices.values()].sort(byTotalDesc),
    serverTime: new Date().toISOString(),
  });
}
interface PricingRow {
  provider: string;
  model: string;
  currency: string;
  input_per_mtok: number;
  cached_input_per_mtok: number;
  cache_write_per_mtok: number;
  output_per_mtok: number;
  updated_at: string;
}

async function handlePricingList(env: Env, principal: Principal): Promise<Response> {
  const result = await env.DB.prepare(
    `SELECT provider, model, currency, input_per_mtok, cached_input_per_mtok, cache_write_per_mtok, output_per_mtok, updated_at
       FROM model_pricing WHERE user_id = ? ORDER BY provider, model`,
  ).bind(principal.userId).all<PricingRow>();

  return json({
    pricing: result.results.map((row) => ({
      provider: row.provider,
      model: row.model,
      currency: row.currency,
      inputPerMtok: row.input_per_mtok,
      cachedInputPerMtok: row.cached_input_per_mtok,
      cacheWritePerMtok: row.cache_write_per_mtok,
      outputPerMtok: row.output_per_mtok,
      updatedAt: row.updated_at,
    })),
    serverTime: new Date().toISOString(),
  });
}

async function handlePricingUpsert(request: Request, env: Env, principal: Principal): Promise<Response> {
  const body = requireObject(await readJSONWithLimit(request, MAX_REQUEST_BYTES), "请求体");
  const provider = requireString(body.provider, "provider", 200).toLowerCase();
  const model = requireString(body.model, "model", 200).toLowerCase();
  const currency = requireString(body.currency, "currency", 3).toLowerCase();
  if (!ALLOWED_CURRENCIES.has(currency)) {
    throw new HTTPError(400, "invalid_currency", "currency 必须是 usd 或 cny");
  }
  const inputPerMtok = requirePrice(body.inputPerMtok, "inputPerMtok");
  const cachedInputPerMtok = requirePrice(body.cachedInputPerMtok, "cachedInputPerMtok");
  const cacheWritePerMtok = requirePrice(body.cacheWritePerMtok, "cacheWritePerMtok");
  const outputPerMtok = requirePrice(body.outputPerMtok, "outputPerMtok");

  await env.DB.prepare(
    `INSERT INTO model_pricing(
       user_id, provider, model, currency,
       input_per_mtok, cached_input_per_mtok, cache_write_per_mtok, output_per_mtok, updated_at
     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
     ON CONFLICT(user_id, provider, model) DO UPDATE SET
       currency = excluded.currency,
       input_per_mtok = excluded.input_per_mtok,
       cached_input_per_mtok = excluded.cached_input_per_mtok,
       cache_write_per_mtok = excluded.cache_write_per_mtok,
       output_per_mtok = excluded.output_per_mtok,
       updated_at = CURRENT_TIMESTAMP`,
  ).bind(principal.userId, provider, model, currency, inputPerMtok, cachedInputPerMtok, cacheWritePerMtok, outputPerMtok).run();

  return json({ ok: true, provider, model, serverTime: new Date().toISOString() });
}

async function handlePricingDelete(url: URL, env: Env, principal: Principal): Promise<Response> {
  const provider = requireString(url.searchParams.get("provider"), "provider", 200).toLowerCase();
  const model = requireString(url.searchParams.get("model"), "model", 200).toLowerCase();
  await env.DB.prepare(
    "DELETE FROM model_pricing WHERE user_id = ? AND provider = ? AND model = ?",
  ).bind(principal.userId, provider, model).run();
  return json({ ok: true, serverTime: new Date().toISOString() });
}

function statsRange(url: URL): { from: string; to: string } {
  const fromParam = url.searchParams.get("from");
  const toParam = url.searchParams.get("to");
  if (fromParam !== null || toParam !== null) {
    const from = requireDay(fromParam, "from");
    const to = requireDay(toParam, "to");
    const range = dayDifference(from, to);
    if (range < 0 || range > 365) {
      throw new HTTPError(400, "invalid_date_range", "日期范围必须为 1～366 天");
    }
    return { from, to };
  }

  let days = 30;
  const daysParam = url.searchParams.get("days");
  if (daysParam !== null) {
    const parsed = Number(daysParam);
    if (!Number.isSafeInteger(parsed) || parsed < 1 || parsed > 366) {
      throw new HTTPError(400, "invalid_field", "days 必须是 1～366 的整数");
    }
    days = parsed;
  }
  const toTime = Date.now();
  const to = new Date(toTime).toISOString().slice(0, 10);
  const from = new Date(toTime - (days - 1) * 86_400_000).toISOString().slice(0, 10);
  return { from, to };
}

function requirePrice(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0 || value > MAX_PRICE_PER_MTOK) {
    throw new HTTPError(400, "invalid_field", `${field} 必须是 0～${MAX_PRICE_PER_MTOK} 的数字`);
  }
  return value;
}

function validateSyncInput(value: unknown): SyncInput {
  const object = requireObject(value, "请求体");
  if (object.schemaVersion !== 1) {
    throw new HTTPError(400, "unsupported_schema", "仅支持 schemaVersion=1");
  }

  const deviceObject = requireObject(object.device, "device");
  const device: DeviceInput = {
    id: requireDeviceId(deviceObject.id),
    name: requireString(deviceObject.name, "device.name", 100),
    appVersion: requireString(deviceObject.appVersion, "device.appVersion", 50),
  };

  if (!Array.isArray(object.days) || object.days.length > MAX_SYNC_DAYS) {
    throw new HTTPError(400, "invalid_days", `days 必须是数组且最多 ${MAX_SYNC_DAYS} 天`);
  }

  const dayNames = new Set<string>();
  const days = object.days.map((rawDay, dayIndex): DayInput => {
    const dayObject = requireObject(rawDay, `days[${dayIndex}]`);
    const day = requireDay(dayObject.day, `days[${dayIndex}].day`);
    if (dayNames.has(day)) throw new HTTPError(400, "duplicate_day", `日期重复：${day}`);
    dayNames.add(day);

    const revision = requireSafeInteger(dayObject.revision, `days[${dayIndex}].revision`, 1);
    if (!Array.isArray(dayObject.usages) || dayObject.usages.length > MAX_USAGES_PER_DAY) {
      throw new HTTPError(400, "invalid_usages", `每天最多 ${MAX_USAGES_PER_DAY} 条模型明细`);
    }

    const usageNames = new Set<string>();
    const usages = dayObject.usages.map((rawUsage, usageIndex): UsageInput => {
      const path = `days[${dayIndex}].usages[${usageIndex}]`;
      const usageObject = requireObject(rawUsage, path);
      const source = requireString(usageObject.source, `${path}.source`, 20);
      if (!ALLOWED_SOURCES.has(source)) throw new HTTPError(400, "invalid_source", `${path}.source 无效`);

      const usage: UsageInput = {
        source,
        provider: requireString(usageObject.provider, `${path}.provider`, 200),
        model: requireString(usageObject.model, `${path}.model`, 200),
        inputTokens: requireSafeInteger(usageObject.inputTokens, `${path}.inputTokens`, 0),
        cachedInputTokens: requireSafeInteger(usageObject.cachedInputTokens, `${path}.cachedInputTokens`, 0),
        cacheWriteTokens: requireSafeInteger(usageObject.cacheWriteTokens, `${path}.cacheWriteTokens`, 0),
        outputTokens: requireSafeInteger(usageObject.outputTokens, `${path}.outputTokens`, 0),
        reasoningTokens: requireSafeInteger(usageObject.reasoningTokens, `${path}.reasoningTokens`, 0),
      };
      const id = usageId(usage);
      if (usageNames.has(id)) throw new HTTPError(400, "duplicate_usage", `${path} 与当天其他明细重复`);
      usageNames.add(id);
      return usage;
    });

    return { day, revision, usages };
  });

  return { schemaVersion: 1, device, days };
}

async function readJSONWithLimit(request: Request, limit: number): Promise<unknown> {
  if (!request.body) throw new HTTPError(400, "empty_body", "请求体不能为空");
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;

  while (true) {
    const item = await reader.read();
    if (item.done) break;
    total += item.value.byteLength;
    if (total > limit) {
      await reader.cancel("request_too_large");
      throw new HTTPError(413, "request_too_large", "请求体超过 1 MB");
    }
    chunks.push(item.value);
  }

  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }

  try {
    return JSON.parse(new TextDecoder().decode(bytes)) as unknown;
  } catch {
    throw new HTTPError(400, "invalid_json", "请求体不是有效 JSON");
  }
}

function requireObject(value: unknown, field: string): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new HTTPError(400, "invalid_field", `${field} 必须是对象`);
  }
  return value as Record<string, unknown>;
}

function requireString(value: unknown, field: string, maxLength: number): string {
  if (typeof value !== "string") throw new HTTPError(400, "invalid_field", `${field} 必须是字符串`);
  const trimmed = value.trim();
  if (!trimmed || trimmed.length > maxLength) {
    throw new HTTPError(400, "invalid_field", `${field} 不能为空且最长 ${maxLength} 字符`);
  }
  return trimmed;
}

function requireDeviceId(value: unknown): string {
  const id = requireString(value, "device.id", 64);
  if (!/^[A-Za-z0-9_-]{8,64}$/.test(id)) {
    throw new HTTPError(400, "invalid_device_id", "device.id 格式无效");
  }
  return id;
}

function requireSafeInteger(value: unknown, field: string, minimum: number): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < minimum) {
    throw new HTTPError(400, "invalid_field", `${field} 必须是大于等于 ${minimum} 的安全整数`);
  }
  return value;
}

function requireDay(value: unknown, field: string): string {
  const day = requireString(value, field, 10);
  const parsed = new Date(`${day}T00:00:00Z`);
  if (
    !/^\d{4}-\d{2}-\d{2}$/.test(day)
    || Number.isNaN(parsed.valueOf())
    || parsed.toISOString().slice(0, 10) !== day
  ) {
    throw new HTTPError(400, "invalid_day", `${field} 必须是 yyyy-MM-dd`);
  }
  return day;
}

function dayDifference(from: string, to: string): number {
  return Math.round((Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / 86_400_000);
}

function usageId(usage: UsageInput): string {
  return `${usage.source}|${usage.provider.toLocaleLowerCase("en-US")}|${usage.model.toLocaleLowerCase("en-US")}`;
}

function shouldUpdateLastUsed(lastUsedAt: string | null): boolean {
  if (!lastUsedAt) return true;
  const timestamp = Date.parse(lastUsedAt.endsWith("Z") ? lastUsedAt : `${lastUsedAt.replace(" ", "T")}Z`);
  return Number.isNaN(timestamp) || Date.now() - timestamp > 3_600_000;
}

async function sha256Bytes(value: string): Promise<Uint8Array> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return new Uint8Array(digest);
}

function hexToBytes(value: string): Uint8Array {
  if (!/^[0-9a-f]{64}$/i.test(value)) return new Uint8Array();
  const bytes = new Uint8Array(value.length / 2);
  for (let index = 0; index < value.length; index += 2) {
    bytes[index / 2] = Number.parseInt(value.slice(index, index + 2), 16);
  }
  return bytes;
}

function json(value: JSONValue | Record<string, unknown>, init: ResponseInit = {}): Response {
  const headers = new Headers(init.headers);
  headers.set("Content-Type", "application/json; charset=utf-8");
  headers.set("Cache-Control", "no-store");
  headers.set("X-Content-Type-Options", "nosniff");
  return new Response(JSON.stringify(value), { ...init, headers });
}

function html(content: string): Response {
  return new Response(content, {
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

function toErrorResponse(error: unknown): Response {
  if (error instanceof HTTPError) {
    return json({ error: { code: error.code, message: error.message } }, { status: error.status });
  }
  return json({ error: { code: "internal_error", message: "服务内部错误" } }, { status: 500 });
}
