## Account migration — credentials must be regenerated (2026-08-18)

The code now validates `com.smidgecraft.Fil` and the `.extra.*` product IDs, and is deployed. **The
App Store Server API credentials are still the old account's and must be replaced before launch.**

`APPSTORE_ISSUER_ID` is per App Store Connect account and the `.p8` In-App Purchase key is issued
inside one, so neither survives the move to the new individual account (team T89Z7YKXVC). The old
org account lapses around 2026-08-20; these die with it whether or not they work today.

Regenerate from the new account — App Store Connect → Users and Access → Integrations → In-App
Purchase — then:

```
wrangler secret put APPSTORE_ISSUER_ID
wrangler secret put APPSTORE_KEY_ID
wrangler secret put APPSTORE_PRIVATE_KEY
```

**This fails closed.** `entitledOriginalId` returning null produces a 403 "Fil Pro is required to
surface", so stale credentials do not degrade quietly — every paying subscriber is denied every AI
feature, and the app cannot tell that apart from not having subscribed.

# Fil surfacing proxy

A Cloudflare Worker that holds the Anthropic API key server-side so it never ships in the app. The
app POSTs `{ query, fils }`; the Worker asks Claude (Haiku) to surface the relevant fils and returns
`{ summary, relevant }`.

**Phase 1 MVP:** no subscription check yet — access is gated only by a shared-secret header
(`X-Fil-Proxy-Key`). That secret still lives in the app and is extractable, so it's a stopgap;
StoreKit subscription verification + per-user cost attribution replace it in phase 4. Set the
**Anthropic account-level spend cap** in the Anthropic console before going live — the outermost
backstop against runaway cost.

## Contract

`POST /` with headers:
- `X-Fil-Proxy-Key: <PROXY_SHARED_SECRET>`
- `content-type: application/json`

Body:
```json
{ "query": "what am i forgetting?", "fils": [ { "text": "title: snippet", "metadata": "2d ago, note" } ] }
```

Response:
```json
{ "summary": "…", "relevant": [3, 1, 7] }
```
`relevant` is 1-based indexes into the `fils` array you sent, best-match first. The app maps those
back to fil UUIDs by position.

## One-time setup

```sh
cd proxy
npm install
npx wrangler login          # opens the browser to your Cloudflare account
```

## Local dev

```sh
cp .dev.vars.example .dev.vars   # then fill in the real key + a random secret
npm run dev                       # serves at http://localhost:8787
```

Point the app at `http://<your-mac-LAN-ip>:8787` (a device can't reach `localhost`) and use the same
secret you put in `.dev.vars`.

## Deploy

```sh
npx wrangler secret put ANTHROPIC_API_KEY     # paste the key
npx wrangler secret put PROXY_SHARED_SECRET   # paste a long random string
npm run deploy                                 # prints the workers.dev URL
```

Then in the app's proxy-config sheet, enter the deployed URL + the same `PROXY_SHARED_SECRET`.

## Testing Fil Pro: dev vs official StoreKit

Local StoreKit purchases (the `Products.storekit` file, run from Xcode) are fake — Apple's servers
never see them, so the real App Store Server API can never verify them. A single proxy secret,
`DEV_BYPASS`, flips between trusting the app (for local testing) and full Apple verification:

```sh
./switch-storekit.sh dev       # Apple verification OFF — test with the local Products.storekit
./switch-storekit.sh official  # real verification ON — use a sandbox tester
./switch-storekit.sh status    # show current mode
```

The app never changes between modes — it always sends the transaction id; the proxy decides whether
to trust it. Secure by default: anything other than `DEV_BYPASS=1` (including unset) means full
verification, so production is safe even if you forget to switch back.

Also flip the Xcode side to match: **Product → Scheme → Edit Scheme → Run → Options → StoreKit
Configuration** = `Products.storekit` for dev, `None` (+ a sandbox tester) for official.

## Smoke test

```sh
curl -sS https://<your-worker>.workers.dev \
  -H "X-Fil-Proxy-Key: <PROXY_SHARED_SECRET>" \
  -H "content-type: application/json" \
  -d '{"query":"test","fils":[{"text":"bought milk","metadata":"1d ago, note"}]}'
```
