import { AnthropicMealAnalysis } from "./anthropic";
import { handle } from "./handler";

export interface Env {
  /** Anthropic API key. Set with `wrangler secret put ANTHROPIC_API_KEY`. */
  ANTHROPIC_API_KEY: string;
  /** Shared secret the iOS app sends as a bearer token. Set with `wrangler secret put DEVICE_TOKEN`. */
  DEVICE_TOKEN: string;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    return handle(request, {
      deviceToken: env.DEVICE_TOKEN,
      provider: new AnthropicMealAnalysis(env.ANTHROPIC_API_KEY),
    });
  },
} satisfies ExportedHandler<Env>;
