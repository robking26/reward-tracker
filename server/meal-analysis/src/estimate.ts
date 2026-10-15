import { z } from "zod";

/**
 * The response contract shared with the iOS app (`NutritionEstimate` in
 * FitnessVault/Services/Meals/MealAnalysis.swift). Keep the two in sync.
 */
export const NutritionEstimateSchema = z.object({
  name: z.string().min(1).max(120),
  items: z.array(z.string().min(1).max(80)).max(20),
  portionDescription: z.string().max(200),
  kilocalories: z.number().int().min(0).max(10_000),
  proteinGrams: z.number().int().min(0).max(1_000),
  carbohydrateGrams: z.number().int().min(0).max(1_500),
  fatGrams: z.number().int().min(0).max(1_000),
  confidence: z.enum(["low", "medium", "high"]),
});

export type NutritionEstimate = z.infer<typeof NutritionEstimateSchema>;

/** What the model returns: the estimate plus whether the photo shows food at all. */
export const ModelOutputSchema = NutritionEstimateSchema.extend({
  isFood: z.boolean(),
});

/** JSON Schema for structured output. Mirrors `ModelOutputSchema`. */
export const modelOutputJSONSchema = {
  type: "object",
  properties: {
    isFood: { type: "boolean", description: "False if the photo does not show food or drink." },
    name: { type: "string", description: "Short, natural meal name, e.g. 'Chicken Caesar salad'." },
    items: { type: "array", items: { type: "string" }, description: "Individual foods visible." },
    portionDescription: { type: "string", description: "Brief description of the estimated portion sizes." },
    kilocalories: { type: "integer" },
    proteinGrams: { type: "integer" },
    carbohydrateGrams: { type: "integer" },
    fatGrams: { type: "integer" },
    confidence: { type: "string", enum: ["low", "medium", "high"] },
  },
  required: [
    "isFood", "name", "items", "portionDescription", "kilocalories",
    "proteinGrams", "carbohydrateGrams", "fatGrams", "confidence",
  ],
  additionalProperties: false,
} as const;

/**
 * Open models sometimes return numbers as strings, decimals or "Medium". Tidy those
 * into the strict shape before validating. Anything still invalid is rejected.
 */
export function normaliseModelOutput(raw: unknown): unknown {
  if (typeof raw !== "object" || raw === null) return raw;
  const input = raw as Record<string, unknown>;
  const whole = (value: unknown) => {
    const number = typeof value === "string" ? Number(value.replace(/[^0-9.\-]/g, "")) : value;
    return typeof number === "number" && Number.isFinite(number) ? Math.round(number) : value;
  };
  const isFood = input.isFood === "false" ? false : input.isFood === "true" ? true : input.isFood;
  return {
    ...input,
    isFood,
    items: Array.isArray(input.items) ? input.items.map(String).filter((item) => item.trim() !== "").slice(0, 20) : [],
    portionDescription: typeof input.portionDescription === "string" ? input.portionDescription.slice(0, 200) : "",
    name: typeof input.name === "string" ? input.name.trim().slice(0, 120) : input.name,
    kilocalories: whole(input.kilocalories),
    proteinGrams: whole(input.proteinGrams),
    carbohydrateGrams: whole(input.carbohydrateGrams),
    fatGrams: whole(input.fatGrams),
    confidence: typeof input.confidence === "string" ? input.confidence.trim().toLowerCase() : input.confidence,
  };
}

/** Parses a model's reply (a JSON string or an already-parsed object) into a result. */
export function parseModelReply(reply: unknown):
  | { kind: "estimate"; estimate: NutritionEstimate }
  | { kind: "notFood" }
  | { kind: "invalid" } {
  let json: unknown = reply;
  if (typeof reply === "string") {
    // Tolerate a stray code fence around the JSON.
    const text = reply.trim().replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "");
    try {
      json = JSON.parse(text);
    } catch {
      return { kind: "invalid" };
    }
  }
  const normalised = normaliseModelOutput(json) as Record<string, unknown>;
  if (normalised?.isFood === false) return { kind: "notFood" };
  const parsed = ModelOutputSchema.safeParse(normalised);
  if (!parsed.success) return { kind: "invalid" };
  const { isFood, ...estimate } = parsed.data;
  return isFood ? { kind: "estimate", estimate } : { kind: "notFood" };
}
