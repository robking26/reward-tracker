import Anthropic from "@anthropic-ai/sdk";
import { ModelOutputSchema, modelOutputJSONSchema } from "./estimate";
import { ProviderError, type AnalysisResult, type MealAnalysisProvider } from "./provider";

export const MODEL = "claude-opus-5-5";

const SYSTEM_PROMPT = `You estimate the nutrition of meals from a single photo for a personal food log.

Identify each visible food and drink, estimate portion sizes from visual cues (plate size, cutlery, packaging), then estimate total calories, protein, carbohydrates and fat for everything shown.

Guidelines:
- Give your best realistic estimate for the whole visible meal. Whole numbers only.
- Account for likely hidden calories such as cooking oil, butter, dressings and sauces when they are typical for the dish.
- Set confidence to "low" when portions or ingredients are hard to judge (mixed dishes, partial views), "high" only for clearly identifiable, standard portions.
- Keep the name short and natural. List the main items separately.
- If the photo does not show food or drink, set isFood to false and use zero for every number.`;

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
        model: MODEL,
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
              { type: "text", text: "Estimate the nutrition of this meal." },
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
    let json: unknown;
    try {
      json = JSON.parse(text);
    } catch {
      return { kind: "unavailable", reason: "The analysis came back in an unexpected format." };
    }
    const parsed = ModelOutputSchema.safeParse(json);
    if (!parsed.success) {
      return { kind: "unavailable", reason: "The analysis came back in an unexpected format." };
    }
    const { isFood, ...estimate } = parsed.data;
    return isFood ? { kind: "estimate", estimate } : { kind: "notFood" };
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

function toBase64(bytes: Uint8Array): string {
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}
