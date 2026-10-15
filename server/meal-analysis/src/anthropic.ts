import Anthropic from "@anthropic-ai/sdk";
import { modelOutputJSONSchema, parseModelReply } from "./estimate";
import { SYSTEM_PROMPT, USER_PROMPT, toBase64 } from "./prompt";
import { ProviderError, type AnalysisResult, type MealAnalysisProvider } from "./provider";

export const ANTHROPIC_MODEL = "claude-opus-5-5";


/** Meal analysis with Claude. The photo is sent only for this request and is not stored by this server. */
export class AnthropicMealAnalysis implements MealAnalysisProvider {
  private readonly client: Anthropic;

  constructor(apiKey: string) {
    // Retries cover 408/409/429/5xx and connection errors; keep the total under the app's 45 s timeout.
    this.client = new Anthropic({ apiKey, maxRetries: 1, timeout: 20_000 });
  }

  async analyse(jpeg: Uint8Array): Promise<AnalysisResult> {
    let response: Anthropic.Beta.BetaMessage;
    try {
      response = await this.client.beta.messages.create({
        model: ANTHROPIC_MODEL,
        max_tokens: 16000,
        // If a safety classifier declines, retry server-side on Anthropic's recommended fallback model.
        betas: ["server-side-fallback-2026-07-01"],
        fallbacks: "default",
        output_config: {
          effort: "medium",
          format: { type: "json_schema", schema: modelOutputJSONSchema },
        },
        system: SYSTEM_PROMPT,
        messages: [
          {
            role: "user",
            content: [
              { type: "image", source: { type: "base64", media_type: "image/jpeg", data: toBase64(jpeg) } },
              { type: "text", text: USER_PROMPT },
            ],
          },
        ],
      });
    } catch (error) {
      throw mapError(error);
    }

    if (response.stop_reason === "refusal") {
      return { kind: "unavailable", reason: "This photo couldn't be analysed." };
    }
    if (response.stop_reason === "max_tokens") {
      return { kind: "unavailable", reason: "The analysis was cut short. Please try again." };
    }

    const text = response.content
      .flatMap((block) => (block.type === "text" ? [block.text] : []))
      .join("");
    const result = parseModelReply(text);
    if (result.kind === "invalid") {
      return { kind: "unavailable", reason: "The analysis came back in an unexpected format." };
    }
    return result;
  }
}

function mapError(error: unknown): ProviderError {
  if (error instanceof Anthropic.RateLimitError) {
    return new ProviderError("rateLimited", "The analysis service is busy. Please try again shortly.");
  }
  if (error instanceof Anthropic.AuthenticationError || error instanceof Anthropic.PermissionDeniedError) {
    return new ProviderError("misconfigured", "The analysis server isn't configured correctly.");
  }
  if (error instanceof Anthropic.APIConnectionError) {
    return new ProviderError("upstream", "Couldn't reach the analysis service. Please try again.");
  }
  if (error instanceof Anthropic.APIError) {
    return new ProviderError("upstream", "The analysis service returned an error. Please try again.");
  }
  return new ProviderError("upstream", "Something went wrong analysing the photo.");
}
