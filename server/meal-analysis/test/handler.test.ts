import { describe, expect, it } from "vitest";
import { bearerMatches, handle, MAX_IMAGE_BYTES } from "../src/handler";
import type { AnalysisResult, MealAnalysisProvider } from "../src/provider";
import { ProviderError } from "../src/provider";
import { ModelOutputSchema } from "../src/estimate";

const TOKEN = "test-device-token";
const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]);
const ESTIMATE = {
  name: "Chicken and rice", items: ["Chicken", "Rice"], portionDescription: "One plate",
  kilocalories: 640, proteinGrams: 48, carbohydrateGrams: 72, fatGrams: 15, confidence: "medium" as const,
};

function provider(result: AnalysisResult | Error): MealAnalysisProvider & { calls: number } {
  return {
    calls: 0,
    async analyse() {
      this.calls++;
      if (result instanceof Error) throw result;
      return result;
    },
  };
}

function post(body: Uint8Array, headers: Record<string, string> = {}): Request {
  return new Request("https://example.com/analyse", {
    method: "POST",
    headers: { Authorization: `Bearer ${TOKEN}`, "Content-Type": "image/jpeg", ...headers },
    body,
  });
}

describe("handle", () => {
  it("returns the estimate for an authorised JPEG", async () => {
    const response = await handle(post(JPEG), { deviceToken: TOKEN, provider: provider({ kind: "estimate", estimate: ESTIMATE }) });
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual(ESTIMATE);
  });

  it("rejects a wrong token without calling the provider", async () => {
    const p = provider({ kind: "estimate", estimate: ESTIMATE });
    const response = await handle(post(JPEG, { Authorization: "Bearer nope" }), { deviceToken: TOKEN, provider: p });
    expect(response.status).toBe(401);
    expect(p.calls).toBe(0);
  });

  it("refuses to run without a configured token", async () => {
    const response = await handle(post(JPEG), { deviceToken: undefined, provider: provider({ kind: "notFood" }) });
    expect(response.status).toBe(500);
  });

  it("rejects non-JPEG bodies", async () => {
    const response = await handle(post(new Uint8Array([1, 2, 3, 4])), { deviceToken: TOKEN, provider: provider({ kind: "notFood" }) });
    expect(response.status).toBe(415);
  });

  it("rejects oversized photos", async () => {
    const big = new Uint8Array(MAX_IMAGE_BYTES + 1);
    big.set(JPEG);
    const response = await handle(post(big), { deviceToken: TOKEN, provider: provider({ kind: "notFood" }) });
    expect(response.status).toBe(413);
  });

  it("explains non-food photos", async () => {
    const response = await handle(post(JPEG), { deviceToken: TOKEN, provider: provider({ kind: "notFood" }) });
    expect(response.status).toBe(422);
    expect(await response.json()).toHaveProperty("error");
  });

  it("maps provider rate limits to 503", async () => {
    const response = await handle(post(JPEG), {
      deviceToken: TOKEN, provider: provider(new ProviderError("rateLimited", "busy")),
    });
    expect(response.status).toBe(503);
  });

  it("only serves POST /analyse", async () => {
    const config = { deviceToken: TOKEN, provider: provider({ kind: "notFood" }) };
    expect((await handle(new Request("https://example.com/analyse"), config)).status).toBe(405);
    expect((await handle(new Request("https://example.com/other", { method: "POST" }), config)).status).toBe(404);
  });
});

describe("bearerMatches", () => {
  it("accepts only the exact token", async () => {
    expect(await bearerMatches(`Bearer ${TOKEN}`, TOKEN)).toBe(true);
    expect(await bearerMatches(`bearer ${TOKEN}`, TOKEN)).toBe(true);
    expect(await bearerMatches(`Bearer ${TOKEN}x`, TOKEN)).toBe(false);
    expect(await bearerMatches(null, TOKEN)).toBe(false);
    expect(await bearerMatches(TOKEN, TOKEN)).toBe(false);
  });
});

describe("ModelOutputSchema", () => {
  it("rejects negative or fractional values", () => {
    expect(ModelOutputSchema.safeParse({ ...ESTIMATE, isFood: true }).success).toBe(true);
    expect(ModelOutputSchema.safeParse({ ...ESTIMATE, isFood: true, kilocalories: -5 }).success).toBe(false);
    expect(ModelOutputSchema.safeParse({ ...ESTIMATE, isFood: true, proteinGrams: 1.5 }).success).toBe(false);
  });
});
