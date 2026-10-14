import { ProviderError, type MealAnalysisProvider } from "./provider";

/** Photos from the app are resized to 1024 px (~150-400 KB). Anything far larger is rejected. */
export const MAX_IMAGE_BYTES = 3 * 1024 * 1024;

export interface HandlerConfig {
  deviceToken: string | undefined;
  provider: MealAnalysisProvider;
}

/**
 * `POST /analyse` with `Content-Type: image/jpeg` and `Authorization: Bearer <device token>`.
 * Returns a `NutritionEstimate` JSON body, or `{ "error": "..." }` with a non-2xx status.
 * Photos are processed in memory and never stored or logged.
 */
export async function handle(request: Request, config: HandlerConfig): Promise<Response> {
  const url = new URL(request.url);
  if (url.pathname === "/health") return json({ ok: true }, 200);
  if (url.pathname !== "/analyse") return error("Not found.", 404);
  if (request.method !== "POST") return error("Use POST.", 405, { Allow: "POST" });

  if (!config.deviceToken) return error("The analysis server isn't configured correctly.", 500);
  if (!(await bearerMatches(request.headers.get("Authorization"), config.deviceToken))) {
    return error("Not authorised.", 401);
  }

  const type = request.headers.get("Content-Type")?.split(";")[0]?.trim().toLowerCase();
  if (type !== "image/jpeg") return error("Send the photo as image/jpeg.", 415);

  const declared = Number(request.headers.get("Content-Length") ?? "0");
  if (declared > MAX_IMAGE_BYTES) return error("The photo is too large.", 413);
  const body = new Uint8Array(await request.arrayBuffer());
  if (body.byteLength === 0) return error("No photo was sent.", 400);
  if (body.byteLength > MAX_IMAGE_BYTES) return error("The photo is too large.", 413);
  if (!isJPEG(body)) return error("The photo isn't a valid JPEG.", 415);

  try {
    const result = await config.provider.analyse(body);
    switch (result.kind) {
      case "estimate":
        return json(result.estimate, 200);
      case "notFood":
        return error("That doesn't look like food or drink. Try another photo.", 422);
      case "unavailable":
        return error(result.reason, 422);
    }
  } catch (caught) {
    if (caught instanceof ProviderError) {
      const status = caught.kind === "rateLimited" ? 503 : caught.kind === "misconfigured" ? 500 : 502;
      return error(caught.message, status);
    }
    return error("Something went wrong analysing the photo.", 500);
  }
}

function isJPEG(bytes: Uint8Array): boolean {
  return bytes.length > 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
}

/** Constant-time comparison of SHA-256 digests, so the token can't be guessed byte by byte. */
export async function bearerMatches(header: string | null, expected: string): Promise<boolean> {
  const presented = header?.match(/^Bearer\s+(.+)$/i)?.[1]?.trim();
  if (!presented) return false;
  const encoder = new TextEncoder();
  const [a, b] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(presented)),
    crypto.subtle.digest("SHA-256", encoder.encode(expected)),
  ]);
  const left = new Uint8Array(a);
  const right = new Uint8Array(b);
  let diff = 0;
  for (let i = 0; i < left.length; i++) diff |= (left[i] ?? 0) ^ (right[i] ?? 0);
  return diff === 0;
}

function json(body: unknown, status: number, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store", ...headers },
  });
}

function error(message: string, status: number, headers: Record<string, string> = {}): Response {
  return json({ error: message }, status, headers);
}
