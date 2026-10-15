import { AnthropicMealAnalysis } from "./anthropic";
import { handle } from "./handler";
import type { MealAnalysisProvider } from "./provider";
import { ProviderError } from "./provider";
import { WorkersAIMealAnalysis } from "./workersai";

export interface Env {
  /** Cloudflare Workers AI binding (free daily allowance). Declared in wrangler.toml. */
  AI: Ai;
  /** "workers-ai" (default, free) or "anthropic" (Claude, paid per photo). */
  ANALYSIS_PROVIDER?: string;
  /** Only needed when ANALYSIS_PROVIDER is "anthropic". Set with `wrangler secret put ANTHROPIC_API_KEY`. */
  ANTHROPIC_API_KEY?: string;
  /** Shared secret the iOS app sends as a bearer token. Set with `wrangler secret put DEVICE_TOKEN`. */
  DEVICE_TOKEN: string;
}

export function providerFor(env: Env): MealAnalysisProvider {
  const choice = (env.ANALYSIS_PROVIDER ?? "workers-ai").trim().toLowerCase();
  if (choice === "anthropic") {
    if (!env.ANTHROPIC_API_KEY) return misconfigured("ANTHROPIC_API_KEY is not set.");
    return new AnthropicMealAnalysis(env.ANTHROPIC_API_KEY);
  }
  if (choice === "workers-ai") {
    if (!env.AI) return misconfigured("The Workers AI binding is missing.");
    return new WorkersAIMealAnalysis(env.AI);
  }
  return misconfigured(`Unknown ANALYSIS_PROVIDER "${choice}".`);
}

function misconfigured(detail: string): MealAnalysisProvider {
  console.error(`Meal analysis misconfigured: ${detail}`);
  return {
    analyse: async () => {
      throw new ProviderError("misconfigured", "The analysis server isn't configured correctly.");
    },
  };
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    return handle(request, { deviceToken: env.DEVICE_TOKEN, provider: providerFor(env) });
  },
} satisfies ExportedHandler<Env>;
