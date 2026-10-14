# Meal analysis server

A small Cloudflare Worker that the iOS app calls to estimate a meal's nutrition from a photo. It holds the AI provider's API key, so the key never ships inside the app.

- **Endpoint:** `POST /analyse`, sent with `Content-Type: image/jpeg` and `Authorization: Bearer <DEVICE_TOKEN>`.
- **Response:** `NutritionEstimate` JSON, or `{ "error": "..." }` with a non-2xx status.
- **Provider:** Claude (`claude-opus-5-5`) using structured JSON output. If Claude declines a request on safety grounds, `fallbacks: "default"` re-runs it on Anthropic's recommended fallback model. Other providers can be added by implementing `MealAnalysisProvider` in `src/provider.ts`.
- **Privacy:** each photo is processed in memory and passed only to the AI provider for that one request. This server never stores or logs photos.

## Cost

There is no free AI tier here. Each photo is billed by Anthropic per token, at the rates on [Anthropic's pricing page](https://www.anthropic.com/pricing).

- **Do this first:** set a monthly spend limit in the Anthropic Console.
- **Price per photo:** depends on the photo size and how long the model reasons, so check your Console usage after a few real photos.
- **Hosting:** Cloudflare Workers' free plan covers this usage level.

## One-time setup

You need a Cloudflare account and an Anthropic account. Both have free sign-up.

1. **Anthropic API key.** In [console.anthropic.com](https://console.anthropic.com), create an API key and set a spend limit.
2. **Device token.** Make one with `openssl rand -hex 32` or a password manager. It's the shared secret between your iPhone and the server.
3. **Cloudflare API token.** In the Cloudflare dashboard, go to My Profile → API Tokens → Create Token and use the **Edit Cloudflare Workers** template. Also copy your **Account ID** from the Workers overview page.
4. **GitHub secrets.** In this repository, go to Settings → Secrets and variables → Actions and add four secrets:
   - `CLOUDFLARE_API_TOKEN`
   - `CLOUDFLARE_ACCOUNT_ID`
   - `ANTHROPIC_API_KEY`
   - `DEVICE_TOKEN`
5. **Deploy.** In GitHub, go to Actions → **Meal analysis server** → Run workflow, tick **deploy** and run it. The log prints the Worker's URL, for example `https://fitness-vault-meal-analysis.<you>.workers.dev`.
6. **Connect the app.** In the app, open Settings → AI meal logging:
   - Set Analysis to **Your analysis server**.
   - Enter `https://…workers.dev/analyse`.
   - Paste the device token.

To rotate a key, update the GitHub secret and run the deploy again.

## Local development

```bash
cd server/meal-analysis
npm install
npm run typecheck
npm test

# Run locally with real keys (never commit this file):
printf 'ANTHROPIC_API_KEY=sk-ant-...\nDEVICE_TOKEN=dev-token\n' > .dev.vars
npm run dev
curl -X POST http://localhost:8787/analyse \
  -H "Authorization: Bearer dev-token" -H "Content-Type: image/jpeg" \
  --data-binary @meal.jpg
```
