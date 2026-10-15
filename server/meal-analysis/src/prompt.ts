/** Shared by every provider so estimates are comparable whichever model runs. */
export const SYSTEM_PROMPT = `You estimate the nutrition of meals from a single photo for a personal food log.

Identify each visible food and drink, estimate portion sizes from visual cues (plate size, cutlery, packaging), then estimate total calories, protein, carbohydrates and fat for everything shown.

Guidelines:
- Give your best realistic estimate for the whole visible meal. Whole numbers only.
- Account for likely hidden calories such as cooking oil, butter, dressings and sauces when they are typical for the dish.
- Set confidence to "low" when portions or ingredients are hard to judge (mixed dishes, partial views), "high" only for clearly identifiable, standard portions.
- Keep the name short and natural. List the main items separately.
- If the photo does not show food or drink, set isFood to false and use zero for every number.

Reply with JSON only, using exactly these fields: isFood, name, items, portionDescription, kilocalories, proteinGrams, carbohydrateGrams, fatGrams, confidence.`;

export const USER_PROMPT = "Estimate the nutrition of this meal.";

export function toBase64(bytes: Uint8Array): string {
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}
