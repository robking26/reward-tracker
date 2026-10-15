import { describe, expect, it } from "vitest";
import { normaliseModelOutput, parseModelReply } from "../src/estimate";
import { providerFor, type Env } from "../src/index";
import { ProviderError } from "../src/provider";
import { WorkersAIMealAnalysis, WORKERS_AI_MODEL, type WorkersAIBinding } from "../src/workersai";

const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0]);
const REPLY = {
  isFood: true, name: "Porridge with berries", items: ["Oats", "Milk", "Blueberries"],
  portionDescription: "One bowl", kilocalories: 380, proteinGrams: 14, carbohydrateGrams: 58,
  fatGrams: 9, confidence: "medium",
};

function fakeAI(result: unknown | Error): WorkersAIBinding & { calls: { model: string; inputs: Record<string, unknown> }[] } {
  const calls: { model: string; inputs: Record<string, unknown> }[] = [];
  return {
    calls,
    async run(model, inputs) {
      calls.push({ model, inputs });
      if (result instanceof Error) throw result;
      return result;
    },
  };
}

describe("WorkersAIMealAnalysis", () => {
  it("sends the photo as a data URL with a JSON schema and returns the estimate", async () => {
    const ai = fakeAI({ response: JSON.stringify(REPLY) });
    const result = await new WorkersAIMealAnalysis(ai).analyse(JPEG);
    const { isFood: _isFood, ...estimate } = REPLY;
    expect(result).toEqual({ kind: "estimate", estimate });
    expect(ai.calls[0]?.model).toBe(WORKERS_AI_MODEL);
    const messages = ai.calls[0]?.inputs.messages as { content: unknown }[];
    expect(JSON.stringify(messages[1]?.content)).toContain("data:image/jpeg;base64,");
    expect(ai.calls[0]?.inputs.response_format).toMatchObject({ type: "json_schema" });
  });

  it("accepts an already-parsed object response", async () => {
    const result = await new WorkersAIMealAnalysis(fakeAI({ response: REPLY })).analyse(JPEG);
    expect(result.kind).toBe("estimate");
  });

  it("reports non-food photos", async () => {
    const result = await new WorkersAIMealAnalysis(fakeAI({ response: { ...REPLY, isFood: false } })).analyse(JPEG);
    expect(result).toEqual({ kind: "notFood" });
  });

  it("turns an unusable reply into a friendly message", async () => {
    const result = await new WorkersAIMealAnalysis(fakeAI({ response: "Sorry, I can't help with that." })).analyse(JPEG);
    expect(result.kind).toBe("unavailable");
  });

  it("explains when the free daily allowance is used up", async () => {
    const provider = new WorkersAIMealAnalysis(fakeAI(new Error("4006: you have used up your daily free allocation of 10,000 neurons")));
    await expect(provider.analyse(JPEG)).rejects.toMatchObject({ kind: "rateLimited" });
  });

  it("maps other failures to upstream errors", async () => {
    const provider = new WorkersAIMealAnalysis(fakeAI(new Error("internal error")));
    await expect(provider.analyse(JPEG)).rejects.toBeInstanceOf(ProviderError);
    await expect(provider.analyse(JPEG)).rejects.toMatchObject({ kind: "upstream" });
  });
});

describe("normaliseModelOutput", () => {
  it("tidies loosely formatted numbers and confidence", () => {
    const tidy = normaliseModelOutput({ ...REPLY, kilocalories: "450 kcal", proteinGrams: 21.6, confidence: "High" });
    expect(tidy).toMatchObject({ kilocalories: 450, proteinGrams: 22, confidence: "high" });
  });

  it("strips a code fence around JSON", () => {
    expect(parseModelReply("```json\n" + JSON.stringify(REPLY) + "\n```").kind).toBe("estimate");
  });

  it("still rejects impossible values", () => {
    expect(parseModelReply({ ...REPLY, kilocalories: -100 }).kind).toBe("invalid");
  });
});

describe("providerFor", () => {
  const base = { DEVICE_TOKEN: "t", AI: fakeAI({}) as unknown as Ai } satisfies Partial<Env>;

  it("defaults to Workers AI", () => {
    expect(providerFor(base as Env)).toBeInstanceOf(WorkersAIMealAnalysis);
  });

  it("refuses Claude without an API key", async () => {
    const provider = providerFor({ ...base, ANALYSIS_PROVIDER: "anthropic" } as Env);
    await expect(provider.analyse(JPEG)).rejects.toMatchObject({ kind: "misconfigured" });
  });
});
