// 内置默认定价目录：与客户端 zfstatmenus/Models/TokenUsage.swift 的
// ModelPricingCatalog 保持一致（匹配顺序、规则与单价），作为用户自定义
// 定价（model_pricing 表）的缺省回退。修改任一侧时请同步另一侧。
// 标准公开 API 单价，最后核对日期：2026-07-16。官方来源见仓库 README。

export type PricingCurrency = "usd" | "cny";

export type ModelPricing = {
  currency: PricingCurrency;
  inputPerMtok: number;
  cachedInputPerMtok: number;
  cacheWritePerMtok: number;
  outputPerMtok: number;
};

export type TokenSums = {
  inputTokens: number;
  cachedInputTokens: number;
  cacheWriteTokens: number;
  outputTokens: number;
  reasoningTokens: number;
};

function usd(input: number, cached: number, write: number, output: number): ModelPricing {
  return { currency: "usd", inputPerMtok: input, cachedInputPerMtok: cached, cacheWritePerMtok: write, outputPerMtok: output };
}

function cny(input: number, cached: number, write: number, output: number): ModelPricing {
  return { currency: "cny", inputPerMtok: input, cachedInputPerMtok: cached, cacheWritePerMtok: write, outputPerMtok: output };
}

export function builtinPricing(rawProvider: string, rawModel: string): ModelPricing | null {
  const provider = rawProvider.toLowerCase();
  const model = rawModel.toLowerCase();

  // provider 是采集来源，不代表模型厂商。同名已知模型始终使用其第一方公开价格。
  if (model === "gpt-5.6-sol-pro" || model.startsWith("gpt-5.6-sol-pro-")) {
    return null;
  }
  // 先匹配 pro，避免被同系列标准型号的前缀规则吞掉。
  if (model === "gpt-5.5-pro" || model.startsWith("gpt-5.5-pro-")) {
    return usd(30, 30, 30, 180);
  }
  if (model === "gpt-5.2-codex" || model.startsWith("gpt-5.2-codex-")) {
    return usd(1.75, 0.175, 1.75, 14);
  }
  if (model === "gpt-5.2" || model.startsWith("gpt-5.2-20")) {
    return usd(1.75, 0.175, 1.75, 14);
  }
  if (model === "gpt-5.4" || model.startsWith("gpt-5.4-20")) {
    return usd(2.5, 0.25, 2.5, 15);
  }
  if (model === "gpt-5.5" || model.startsWith("gpt-5.5-")) {
    return usd(5, 0.5, 6.25, 30);
  }
  if (model === "gpt-5.6-sol" || model.startsWith("gpt-5.6-sol-")) {
    return usd(5, 0.5, 6.25, 30);
  }
  if (model === "gpt-5.6-terra" || model.startsWith("gpt-5.6-terra-")) {
    return usd(2.5, 0.25, 3.125, 15);
  }
  if (model === "gpt-5.6-luna" || model.startsWith("gpt-5.6-luna-")) {
    return usd(1, 0.1, 1.25, 6);
  }

  if (model.includes("claude-opus-4-8")) {
    return usd(5, 0.5, 6.25, 25);
  }
  if (model.includes("claude-fable-5")) {
    return usd(10, 1, 12.5, 50);
  }
  if (model.includes("claude-haiku-4-5")) {
    return usd(1, 0.1, 1.25, 5);
  }

  if (model === "glm-5.2" || model.startsWith("glm-5.2-")) {
    return cny(8, 2, 0, 28);
  }
  if (model === "glm-5.1" || model.startsWith("glm-5.1-")) {
    // 聚合日志无法还原每次请求是否跨过 32K 阶梯，采用官方 <32K 档。
    return cny(6, 1.3, 0, 24);
  }

  if (model === "deepseek-v4-pro" || model.startsWith("deepseek-v4-pro-")) {
    return usd(0.435, 0.003625, 0.435, 0.87);
  }

  if (model === "qwen3.7-max" || model.startsWith("qwen3.7-max-")) {
    return cny(12, 12, 12, 36);
  }

  if (model === "kimi-k3" || (model === "k3" && provider === "kimi-code")) {
    // 官方仅区分缓存命中与未命中；缓存创建按未命中输入计价。
    return cny(20, 2, 20, 100);
  }

  if (provider === "llama-cpp" || provider === "llama.cpp") {
    return usd(0, 0, 0, 0);
  }

  return null;
}

export function costForTokens(pricing: ModelPricing, tokens: TokenSums): number {
  const raw = tokens.inputTokens * pricing.inputPerMtok
    + tokens.cachedInputTokens * pricing.cachedInputPerMtok
    + tokens.cacheWriteTokens * pricing.cacheWritePerMtok
    + (tokens.outputTokens + tokens.reasoningTokens) * pricing.outputPerMtok;
  return raw / 1_000_000;
}
