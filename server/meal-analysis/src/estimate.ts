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
