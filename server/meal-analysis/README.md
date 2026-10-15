# Meal analysis server

A small Cloudflare Worker that the iOS app calls to estimate a meal's nutrition from a photo. AI credentials live here, never in the app.

- **Endpoint:** `POST /analyse`, sent with `Content-Type: image/jpeg` and `Authorization: Bearer <DEVICE_TOKEN>`.
- **Response:** `NutritionEstimate` JSON, or `{ "error": "..." }` with a non-2xx status.
- **Privacy:** each photo is processed in memory and sent only to the chosen AI service for that request. This server never stores or logs photos.

## Choosing the AI

| Provider | Setting | Cost | Notes |
|---|---|---|---|
| **Cloudflare Workers AI** (default) | `workers-ai` | Free daily allowance (10,000 "neurons", resets 00:00 UTC). On the Workers Free plan, requests beyond it fail instead of being charged. | Uses Llama 4 Scout (`@cf/meta/llama-4-scout-17b-16e-instruct`). Rougher portion estimates than Claude. No extra account or key. |
| **Claude** | `anthropic` | Paid per photo at [Anthropic's rates](https://www.anthropic.com/pricing). | More accurate. Needs an Anthropic API key, and you should set a spend limit. |

How many photos fit in the free allowance depends on the image and the model. Check **Workers AI** in your Cloudflare dashboard after a day or two of use. When the allowance runs out, the app shows a message and you can still log the meal by typing the numbers.

To switch, run the deploy workflow again and pick the other provider. Every estimate can be edited in the app before you confirm it.

## One-time setup (free option)

You need a free Cloudflare account.

1. **Device token.** On a Mac, open Terminal and run `openssl rand -hex 32`. Copy the result. It's the shared password between your iPhone and the server.
2. **Cloudflare API token.**
   1. Sign up at cloudflare.com.
   2. Go to My Profile → API Tokens → **Create Token** and use the **Edit Cloudflare Workers** template.
   3. Copy the token.
   4. Also copy your **Account ID**, which is on the Workers & Pages overview page.
3. **GitHub secrets.** In this repository, go to Settings → Secrets and variables → Actions → **New repository secret**, and add:
   - `CLOUDFLARE_API_TOKEN`
   - `CLOUDFLARE_ACCOUNT_ID`
   - `DEVICE_TOKEN`
4. **Deploy.**
   1. In GitHub, go to Actions → **Meal analysis server** → **Run workflow**.
   2. Tick **deploy**, leave the provider as `workers-ai`, and run it.
   3. The log prints the Worker's URL, for example `https://fitness-vault-meal-analysis.<you>.workers.dev`.
5. **Connect the app.**
   1. In the app, open ⚙️ → AI meal logging and set Analysis to **Your analysis server**.
   2. Enter the URL followed by `/analyse`.
   3. Paste the device token.

### Optional: use Claude instead

1. In [console.anthropic.com](https://console.anthropic.com), create an API key and set a monthly spend limit.
2. Add it as the `ANTHROPIC_API_KEY` repository secret.
3. Run the deploy workflow with the provider set to `anthropic`.

## Local development

```bash
cd server/meal-analysis
npm install
npm run typecheck
npm test

# Run locally (Workers AI calls go to your Cloudflare account; never commit .dev.vars):
printf 'DEVICE_TOKEN=dev-token\n' > .dev.vars
npx wrangler dev --remote
curl -X POST http://localhost:8787/analyse \
  -H "Authorization: Bearer dev-token" -H "Content-Type: image/jpeg" \
  --data-binary @meal.jpg
```
