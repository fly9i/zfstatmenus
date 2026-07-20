import { SELF, applyD1Migrations, env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";

const token = "zfsm_abcdefghijkl_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopq";
const prefix = "abcdefghijkl";
const otherToken = "zfsm_mnopqrstuvwx_QRSTUVWXYZabcdefghijklmnopqrstuvwxyz1234567";
const otherPrefix = "mnopqrstuvwx";

beforeAll(async () => {
  await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);
});

beforeEach(async () => {
  await env.DB.prepare("DELETE FROM users").run();
  const tokenHash = await sha256Hex(token);
  const otherTokenHash = await sha256Hex(otherToken);
  await env.DB.batch([
    env.DB.prepare("INSERT INTO users(id, display_name) VALUES (?, ?)").bind("user-a", "测试用户"),
    env.DB.prepare("INSERT INTO users(id, display_name) VALUES (?, ?)").bind("user-b", "其他用户"),
    env.DB.prepare(
      "INSERT INTO access_tokens(id, user_id, token_prefix, token_hash, label) VALUES (?, ?, ?, ?, ?)",
    ).bind("token-a", "user-a", prefix, tokenHash, "测试 Token"),
    env.DB.prepare(
      "INSERT INTO access_tokens(id, user_id, token_prefix, token_hash, label) VALUES (?, ?, ?, ?, ?)",
    ).bind("token-b", "user-b", otherPrefix, otherTokenHash, "其他 Token"),
  ]);
});

describe("ZFStatMenus sync Worker", () => {
  it("只公开健康检查，其他接口必须认证", async () => {
    const health = await SELF.fetch("https://example.com/v1/health");
    expect(health.status).toBe(200);

    const unauthorized = await SELF.fetch("https://example.com/v1/me");
    expect(unauthorized.status).toBe(401);

    const noLogin = await SELF.fetch("https://example.com/v1/login", {
      method: "POST",
      headers: authorizationHeaders(),
    });
    expect(noLogin.status).toBe(404);
  });

  it("认证 Token 映射到预置用户", async () => {
    const response = await SELF.fetch("https://example.com/v1/me", {
      headers: authorizationHeaders(),
    });
    expect(response.status).toBe(200);
    const body = await response.json<{ user: { id: string; displayName: string } }>();
    expect(body.user).toEqual({ id: "user-a", displayName: "测试用户" });
  });

  it("按 revision 幂等保存每日完整快照并隔离当前设备", async () => {
    await sync("device-a", "Mac A", 1, 100);
    await sync("device-b", "Mac B", 2, 200);

    // 迟到的旧 revision 不得覆盖较新的设备 B 快照。
    await sync("device-b", "Mac B", 1, 50);

    const response = await SELF.fetch(
      "https://example.com/v1/snapshot?from=2026-07-14&to=2026-07-14&excludeDeviceId=device-a",
      { headers: authorizationHeaders() },
    );
    expect(response.status).toBe(200);
    const body = await response.json<{ rows: Array<{ deviceId: string; inputTokens: number }> }>();
    expect(body.rows).toEqual([{
      deviceId: "device-b",
      deviceName: "Mac B",
      day: "2026-07-14",
      source: "codex",
      provider: "openai",
      model: "gpt-5.2-codex",
      inputTokens: 200,
      cachedInputTokens: 0,
      cacheWriteTokens: 0,
      outputTokens: 0,
      reasoningTokens: 0,
    }]);
  });

  it("不同 Token 所属用户的数据互相不可见", async () => {
    await sync("device-a", "Mac A", 1, 100, token);
    await sync("device-b", "Mac B", 1, 900, otherToken);

    const response = await SELF.fetch(
      "https://example.com/v1/snapshot?from=2026-07-14&to=2026-07-14&excludeDeviceId=unused-device",
      { headers: authorizationHeaders(token) },
    );
    const body = await response.json<{ rows: Array<{ inputTokens: number }> }>();
    expect(body.rows.map((row) => row.inputTokens)).toEqual([100]);
  });

  it("接受并返回 Kimi CLI 用量", async () => {
    await sync("device-a", "Mac A", 1, 100, token, "kimi");

    const response = await SELF.fetch(
      "https://example.com/v1/snapshot?from=2026-07-14&to=2026-07-14&excludeDeviceId=unused-device",
      { headers: authorizationHeaders() },
    );
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      rows: [{ source: "kimi", inputTokens: 100 }],
    });
  });

  it("拒绝不存在的日历日期", async () => {
    const response = await SELF.fetch(
      "https://example.com/v1/snapshot?from=2026-02-31&to=2026-03-01&excludeDeviceId=device-a",
      { headers: authorizationHeaders() },
    );
    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toMatchObject({
      error: { code: "invalid_day" },
    });
  });

  it("根路径返回同步面板页面且无需认证", async () => {
    const response = await SELF.fetch("https://example.com/");
    expect(response.status).toBe(200);
    expect(response.headers.get("Content-Type")).toContain("text/html");
    const text = await response.text();
    expect(text).toContain("ZFStatMenus 同步面板");
  });

  it("统计与定价接口需要认证", async () => {
    const stats = await SELF.fetch("https://example.com/v1/stats");
    expect(stats.status).toBe(401);
    const pricing = await SELF.fetch("https://example.com/v1/pricing");
    expect(pricing.status).toBe(401);
  });

  it("统计接口按远端定价计算费用并汇总各维度", async () => {
    await sync("device-a", "Mac A", 1, 1_000_000);
    await putPricing({ provider: "openai", model: "gpt-5.2-codex", currency: "usd", inputPerMtok: 2 });

    const response = await SELF.fetch(
      "https://example.com/v1/stats?from=2026-07-14&to=2026-07-14",
      { headers: authorizationHeaders() },
    );
    expect(response.status).toBe(200);
    const body = await response.json<{
      days: Array<{ day: string; inputTokens: number; usdCost: number; cnyCost: number }>;
      models: Array<{
        provider: string; model: string; inputTokens: number; usdCost: number; priced: number;
        priceSource: string | null;
        price: { currency: string; inputPerMtok: number; cachedInputPerMtok: number; cacheWritePerMtok: number; outputPerMtok: number } | null;
      }>;
      sources: Array<{ source: string; inputTokens: number }>;
      devices: Array<{ deviceName: string; inputTokens: number }>;
    }>();

    expect(body.models).toEqual([{
      provider: "openai",
      model: "gpt-5.2-codex",
      inputTokens: 1_000_000,
      cachedInputTokens: 0,
      cacheWriteTokens: 0,
      outputTokens: 0,
      reasoningTokens: 0,
      usdCost: 2,
      cnyCost: 0,
      priced: 1,
      priceSource: "user",
      price: { currency: "usd", inputPerMtok: 2, cachedInputPerMtok: 0, cacheWritePerMtok: 0, outputPerMtok: 0 },
    }]);
    expect(body.days[0]).toMatchObject({ day: "2026-07-14", inputTokens: 1_000_000, usdCost: 2, cnyCost: 0 });
    expect(body.sources[0]).toMatchObject({ source: "codex", inputTokens: 1_000_000 });
    expect(body.devices[0]).toMatchObject({ deviceName: "Mac A", inputTokens: 1_000_000 });
  });

  it("未定价模型费用为零并标记 priced=0", async () => {
    await sync("device-a", "Mac A", 1, 1_000_000, token, "codex", "openai", "unknown-internal-model");
    const response = await SELF.fetch(
      "https://example.com/v1/stats?from=2026-07-14&to=2026-07-14",
      { headers: authorizationHeaders() },
    );
    const body = await response.json<{
      models: Array<{ usdCost: number; cnyCost: number; priced: number; priceSource: string | null; price: unknown }>;
    }>();
    expect(body.models[0]).toMatchObject({ usdCost: 0, cnyCost: 0, priced: 0, priceSource: null, price: null });
  });

  it("内置定价目录为已知模型提供默认价格", async () => {
    await sync("device-a", "Mac A", 1, 1_000_000);
    const response = await SELF.fetch(
      "https://example.com/v1/stats?from=2026-07-14&to=2026-07-14",
      { headers: authorizationHeaders() },
    );
    const body = await response.json<{
      models: Array<Record<string, unknown>>;
      days: Array<{ usdCost: number; cnyCost: number }>;
    }>();
    expect(body.models[0]).toMatchObject({
      model: "gpt-5.2-codex",
      usdCost: 1.75,
      cnyCost: 0,
      priced: 1,
      priceSource: "builtin",
      price: { currency: "usd", inputPerMtok: 1.75, cachedInputPerMtok: 0.175, cacheWritePerMtok: 1.75, outputPerMtok: 14 },
    });
    expect(body.days[0]).toMatchObject({ usdCost: 1.75, cnyCost: 0 });
  });

  it("内置定价支持前缀匹配并排除未定价内部型号", async () => {
    await sync("device-a", "Mac A", 1, 1_000_000, token, "codex", "openai", "gpt-5.5-pro-2026");
    await sync("device-b", "Mac B", 1, 1_000_000, token, "zcode", "zcode", "gpt-5.6-sol-pro");

    const response = await SELF.fetch(
      "https://example.com/v1/stats?from=2026-07-14&to=2026-07-14",
      { headers: authorizationHeaders() },
    );
    const body = await response.json<{
      models: Array<{ model: string; usdCost: number; cnyCost: number; priced: number; priceSource: string | null }>;
    }>();
    const pro = body.models.find((m) => m.model === "gpt-5.5-pro-2026");
    const solPro = body.models.find((m) => m.model === "gpt-5.6-sol-pro");
    expect(pro).toMatchObject({ usdCost: 30, cnyCost: 0, priced: 1, priceSource: "builtin" });
    expect(solPro).toMatchObject({ usdCost: 0, cnyCost: 0, priced: 0, priceSource: null });
  });

  it("内置定价支持 CNY 币种模型", async () => {
    await sync("device-a", "Mac A", 1, 1_000_000, token, "zcode", "zhipu", "glm-5.2");
    const response = await SELF.fetch(
      "https://example.com/v1/stats?from=2026-07-14&to=2026-07-14",
      { headers: authorizationHeaders() },
    );
    const body = await response.json<{
      models: Array<{ usdCost: number; cnyCost: number; priced: number; priceSource: string | null }>;
    }>();
    expect(body.models[0]).toMatchObject({ usdCost: 0, cnyCost: 8, priced: 1, priceSource: "builtin" });
  });

  it("定价可按用户增删改查且互相隔离，provider/model 大小写无关", async () => {
    let response = await SELF.fetch("https://example.com/v1/pricing", { headers: authorizationHeaders() });
    expect((await response.json<{ pricing: unknown[] }>()).pricing).toEqual([]);

    await putPricing({
      provider: "OpenAI", model: "GPT-5.2-Codex", currency: "usd",
      inputPerMtok: 1.75, cachedInputPerMtok: 0.175, cacheWritePerMtok: 1.75, outputPerMtok: 14,
    });

    response = await SELF.fetch("https://example.com/v1/pricing", { headers: authorizationHeaders() });
    let body = await response.json<{ pricing: Array<Record<string, unknown>> }>();
    expect(body.pricing).toHaveLength(1);
    expect(body.pricing[0]).toMatchObject({
      provider: "openai", model: "gpt-5.2-codex", currency: "usd",
      inputPerMtok: 1.75, cachedInputPerMtok: 0.175, cacheWritePerMtok: 1.75, outputPerMtok: 14,
    });

    const other = await SELF.fetch("https://example.com/v1/pricing", { headers: authorizationHeaders(otherToken) });
    expect((await other.json<{ pricing: unknown[] }>()).pricing).toEqual([]);

    const del = await SELF.fetch(
      "https://example.com/v1/pricing?provider=OPENAI&model=GPT-5.2-Codex",
      { method: "DELETE", headers: authorizationHeaders() },
    );
    expect(del.status).toBe(200);
    response = await SELF.fetch("https://example.com/v1/pricing", { headers: authorizationHeaders() });
    body = await response.json<{ pricing: Array<Record<string, unknown>> }>();
    expect(body.pricing).toEqual([]);
  });

  it("拒绝非法定价输入", async () => {
    const badCurrency = await putPricingRaw({
      provider: "openai", model: "m", currency: "eur",
      inputPerMtok: 1, cachedInputPerMtok: 0, cacheWritePerMtok: 0, outputPerMtok: 0,
    });
    expect(badCurrency.status).toBe(400);

    const negative = await putPricingRaw({
      provider: "openai", model: "m", currency: "usd",
      inputPerMtok: -1, cachedInputPerMtok: 0, cacheWritePerMtok: 0, outputPerMtok: 0,
    });
    expect(negative.status).toBe(400);
  });
});

async function putPricing(pricing: {
  provider: string;
  model: string;
  currency: string;
  inputPerMtok: number;
  cachedInputPerMtok?: number;
  cacheWritePerMtok?: number;
  outputPerMtok?: number;
}): Promise<void> {
  const response = await putPricingRaw(pricing);
  expect(response.status).toBe(200);
}

function putPricingRaw(pricing: Record<string, unknown>): Promise<Response> {
  return SELF.fetch("https://example.com/v1/pricing", {
    method: "PUT",
    headers: { ...authorizationHeaders(), "Content-Type": "application/json" },
    body: JSON.stringify({
      cachedInputPerMtok: 0,
      cacheWritePerMtok: 0,
      outputPerMtok: 0,
      ...pricing,
    }),
  });
}

async function sync(
  deviceId: string,
  deviceName: string,
  revision: number,
  inputTokens: number,
  accessToken = token,
  source = "codex",
  provider = "openai",
  model = "gpt-5.2-codex",
): Promise<void> {
  const response = await SELF.fetch("https://example.com/v1/sync", {
    method: "POST",
    headers: {
      ...authorizationHeaders(accessToken),
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      schemaVersion: 1,
      device: { id: deviceId, name: deviceName, appVersion: "test" },
      days: [{
        day: "2026-07-14",
        revision,
        usages: [{
          source,
          provider,
          model,
          inputTokens,
          cachedInputTokens: 0,
          cacheWriteTokens: 0,
          outputTokens: 0,
          reasoningTokens: 0,
        }],
      }],
    }),
  });
  expect(response.status).toBe(200);
}

function authorizationHeaders(accessToken = token): Record<string, string> {
  return { Authorization: `Bearer ${accessToken}` };
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}
