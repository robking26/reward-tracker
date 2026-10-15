import { modelOutputJSONSchema, parseModelReply } from "./estimate";
import { SYSTEM_PROMPT, USER_PROMPT, toBase64 } from "./prompt";
import { ProviderError, type AnalysisResult, type MealAnalysisProvider } from "./provider";

/** A vision model on Cloudflare Workers AI that can return JSON matching a schema. */
export const WORKERS_AI_MODEL = "@cf/meta/llama-4-scout-17b-16e-instruct";

/** The subset of the Workers AI binding this provider uses, so tests can supply a fake. */
export interface WorkersAIBinding {
  run(model: string, inputs: Record<string, unknown>): Promise<unknown>;
}

/**
 * Meal analysis on Cloudflare Workers AI. Uses the account's free daily allowance;
 * on the Workers Free plan, requests beyond it fail rather than being billed.
 */
export class WorkersAIMealAnalysis implements MealAnalysisProvider {
  constructor(private readonly ai: WorkersAIBinding) {}

  async analyse(jpeg: Uint8Array): Promise<AnalysisResult> {
    let output: unknown;
    try {
      output = await this.ai.run(WORKERS_AI_MODEL, {
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          {
            role: "user",
            content: [
              { type: "text", text: USER_PROMPT },
              { type: "image_url", image_url: { url: `data:image/jpeg;base64,${toBase64(jpeg)}` } },
            ],
          },
        ],
        response_format: { type: "json_schema", json_schema: modelOutputJSONSchema },
        max_tokens: 1024,
        temperature: 0.2,
      });
    } catch (error) {
      throw mapError(error);
    }

    const reply = (output as { response?: unknown } | null)?.response;
    const result = parseModelReply(reply);
    if (result.kind === "invalid") {
      return { kind: "unavailable", reason: "The analysis came back in an unexpected format. Please try again." };
    }
    return result;
  }
}

function mapError(error: unknown): ProviderError {
  const message = error instanceof Error ? error.message : String(error);
  // The free allowance is counted in "neurons" and resets daily at 00:00 UTC.
  if (/neuron|allocation|quota|rate limit|too many requests|4006|429/i.test(message)) {
    return new ProviderError(
      "rateLimited",
      "Today's free analysis allowance is used up. It resets overnight; you can still log the meal by editing the numbers.",
    );
  }
  return new ProviderError("upstream", "The analysis service returned an error. Please try again.");
}
