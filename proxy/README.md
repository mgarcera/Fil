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

## Smoke test

```sh
curl -sS https://<your-worker>.workers.dev \
  -H "X-Fil-Proxy-Key: <PROXY_SHARED_SECRET>" \
  -H "content-type: application/json" \
  -d '{"query":"test","fils":[{"text":"bought milk","metadata":"1d ago, note"}]}'
```
