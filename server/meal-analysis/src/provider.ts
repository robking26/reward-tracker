import type { NutritionEstimate } from "./estimate";

/** A vision model that estimates nutrition from a meal photo. Swap providers by adding another implementation. */
export interface MealAnalysisProvider {
  analyse(jpeg: Uint8Array): Promise<AnalysisResult>;
}

export type AnalysisResult =
  | { kind: "estimate"; estimate: NutritionEstimate }
  /** The photo doesn't show food or drink. */
  | { kind: "notFood" }
  /** The provider declined or returned something unusable. */
  | { kind: "unavailable"; reason: string };

/** Errors the HTTP layer maps to status codes, so provider details never leak to the client. */
export class ProviderError extends Error {
  constructor(
    readonly kind: "rateLimited" | "misconfigured" | "upstream",
    message: string,
  ) {
    super(message);
  }
}
