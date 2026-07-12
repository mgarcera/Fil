/**
 * Fil surfacing proxy — Cloudflare Worker.
 *
 * Holds the Anthropic API key server-side (never ships in the app) and gates access on a verified
 * Fil Pro subscription. The app sends the subscription's transaction id; the Worker asks Apple's
 * App Store Server API for the live subscription status and only serves Claude for an active
 * subscriber. No shared secret in the app.
 *
 * Secrets (set with `wrangler secret put`, never committed):
 *   ANTHROPIC_API_KEY     — the Anthropic key
 *   APPSTORE_PRIVATE_KEY  — the In-App Purchase .p8 (PKCS#8 PEM)
 *   APPSTORE_KEY_ID       — the key's Key ID
 *   APPSTORE_ISSUER_ID    — the account Issuer ID
 */

const MODEL = "claude-haiku-4-5";
const ANTHROPIC_ENDPOINT = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";
const MAX_TOKENS = 800;

const BUNDLE_ID = "com.masongarcera.Fil";
const PRODUCT_IDS = ["com.masongarcera.Fil.pro.monthly", "com.masongarcera.Fil.pro.annual"];
// Apple subscription status codes that grant entitlement: 1 = active, 4 = billing grace period.
const ENTITLED_STATUSES = [1, 4];
const APPSTORE_PROD = "https://api.storekit.itunes.apple.com";
const APPSTORE_SANDBOX = "https://api.storekit-sandbox.itunes.apple.com";

const SYSTEM_PROMPT = `You help someone explore their own private notes (they call each one a "fil"). Each note is listed as:
  N. (when it was made, its type, whether it has open to-dos) title: snippet
Types are note, voice, link, photo.

Given a query and the list, do two things:

1. Select the notes that genuinely answer the query, best first. Interpret the query flexibly:
- Topic, mood, or kind of thought: pick notes really about it. Be strict; exclude loosely or merely emotionally related ones, and prefer a few tight matches over many loose ones.
- Temporal ("recently", "lately", "what have i forgotten", "what have i missed"): use the dates. Recent/lately = the newest notes; forgotten/missed = older notes from a while ago.
- Type or to-dos ("photos", "links", "voice notes", "to-dos"): use the type and to-do flag.
Return an empty list only if nothing genuinely fits.

2. Reflect back what those selected notes are about, in a warm but grounded way, like a friend who listens well. 2 to 3 sentences, second person, in their voice. Stay close to what's actually written.

Voice rules:
- Warm but restrained. Never sentimental, flowery, or therapeutic. Do not psychoanalyze, infer hidden motives, or reach for deeper meaning the notes don't state.
- Describe what they've been noting about this, not who they are as a person.
- No clinical framing ("there's a tension between", "navigating with intention"), no advice, no nudges.
- Never use em dashes. Use commas, periods, or "and". Contractions welcome.
- Write in natural sentence case (the app handles lowercasing).

Respond with ONLY a JSON object, no prose or code fences:
{"summary": "...", "relevant": [numbers]}`;

export default {
  async fetch(request, env) {
    if (request.method !== "POST") return json({ error: "Use POST." }, 405);

    // Gate: verify an active Fil Pro subscription from the transaction id the app sends.
    const transactionId = request.headers.get("X-Fil-Transaction-Id") || "";
    if (!transactionId) return json({ error: "Fil Pro is required to surface." }, 401);

    let entitled;
    try {
      entitled = await isActiveSubscriber(transactionId, env);
    } catch (e) {
      return json({ error: "Couldn't verify your subscription." }, 502);
    }
    if (!entitled) return json({ error: "Fil Pro is required to surface." }, 403);

    if (!env.ANTHROPIC_API_KEY) return json({ error: "Proxy is missing its Anthropic key." }, 500);

    let body;
    try {
      body = await request.json();
    } catch {
      return json({ error: "Body must be JSON." }, 400);
    }

    const query = typeof body.query === "string" ? body.query.trim() : "";
    const fils = Array.isArray(body.fils) ? body.fils : null;
    if (!query || !fils) return json({ error: "Expected { query, fils: [...] }." }, 400);

    const numbered = fils
      .map((fil, i) => {
        const n = `${i + 1}.`;
        const text = typeof fil.text === "string" ? fil.text : "";
        const meta = typeof fil.metadata === "string" ? fil.metadata : "";
        return meta ? `${n} (${meta}) ${text}` : `${n} ${text}`;
      })
      .join("\n");

    const anthropicBody = {
      model: MODEL,
      max_tokens: MAX_TOKENS,
      system: SYSTEM_PROMPT,
      messages: [
        {
          role: "user",
          content: [
            { type: "text", text: `Notes:\n${numbered}`, cache_control: { type: "ephemeral" } },
            { type: "text", text: `Query: ${query}` },
          ],
        },
      ],
    };

    let upstream;
    try {
      upstream = await fetch(ANTHROPIC_ENDPOINT, {
        method: "POST",
        headers: {
          "x-api-key": env.ANTHROPIC_API_KEY,
          "anthropic-version": ANTHROPIC_VERSION,
          "content-type": "application/json",
        },
        body: JSON.stringify(anthropicBody),
      });
    } catch {
      return json({ error: "Could not reach the model." }, 502);
    }

    if (!upstream.ok) {
      const detail = (await upstream.text()).slice(0, 200);
      return json({ error: `Model request failed (${upstream.status}). ${detail}` }, 502);
    }

    const data = await upstream.json();
    const text = (data.content || []).find((b) => b.type === "text")?.text || "";
    const parsed = parseSurfacing(text);
    if (!parsed) return json({ error: "Couldn't read the model's response." }, 502);

    const u = data.usage || {};
    console.log(
      `surface "${query}": ${parsed.relevant.length} fils | in ${u.input_tokens ?? 0} out ${u.output_tokens ?? 0} cacheRead ${u.cache_read_input_tokens ?? 0}`,
    );

    return json({ summary: parsed.summary, relevant: parsed.relevant }, 200);
  },
};

// MARK: - App Store subscription verification

/**
 * Ask Apple's App Store Server API for the subscription statuses tied to `transactionId` and return
 * true iff one of our products is in an entitled state. Tries production first, then sandbox.
 */
async function isActiveSubscriber(transactionId, env) {
  const token = await appStoreAuthToken(env);
  for (const base of [APPSTORE_PROD, APPSTORE_SANDBOX]) {
    const res = await fetch(`${base}/inApps/v1/subscriptions/${encodeURIComponent(transactionId)}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (res.status === 404) continue; // unknown here — try the other environment
    if (!res.ok) continue;
    const payload = await res.json();
    if (subscriptionActive(payload)) return true;
  }
  return false;
}

function subscriptionActive(payload) {
  for (const group of payload.data || []) {
    for (const tx of group.lastTransactions || []) {
      if (!ENTITLED_STATUSES.includes(tx.status)) continue;
      // The transaction info is a JWS from Apple (trusted TLS channel); read its payload to confirm
      // the product is one of ours, without needing to re-verify the signature.
      const info = decodeJWSPayload(tx.signedTransactionInfo);
      if (info && PRODUCT_IDS.includes(info.productId)) return true;
    }
  }
  return false;
}

/** Build and sign the ES256 JWT that authenticates calls to the App Store Server API. */
async function appStoreAuthToken(env) {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "ES256", kid: env.APPSTORE_KEY_ID, typ: "JWT" };
  const payload = {
    iss: env.APPSTORE_ISSUER_ID,
    iat: now,
    exp: now + 20 * 60,
    aud: "appstoreconnect-v1",
    bid: BUNDLE_ID,
  };
  const signingInput = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}`;
  const key = await importPrivateKey(env.APPSTORE_PRIVATE_KEY);
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${b64urlBytes(new Uint8Array(signature))}`;
}

async function importPrivateKey(pem) {
  const der = pemToDer(pem);
  return crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
}

function pemToDer(pem) {
  const b64 = pem
    .replace(/-----BEGIN [^-]+-----/, "")
    .replace(/-----END [^-]+-----/, "")
    .replace(/\s+/g, "");
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

/** Decode the payload segment of a JWS without verifying its signature. */
function decodeJWSPayload(jws) {
  if (typeof jws !== "string") return null;
  const parts = jws.split(".");
  if (parts.length !== 3) return null;
  try {
    const b64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    return JSON.parse(atob(b64));
  } catch {
    return null;
  }
}

// MARK: - Helpers

function b64url(str) {
  return b64urlBytes(new TextEncoder().encode(str));
}

function b64urlBytes(bytes) {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function parseSurfacing(text) {
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start === -1 || end === -1 || end < start) return null;
  try {
    const obj = JSON.parse(text.slice(start, end + 1));
    const summary = typeof obj.summary === "string" ? obj.summary : "";
    const relevant = Array.isArray(obj.relevant) ? obj.relevant.filter((n) => Number.isInteger(n)) : [];
    return { summary, relevant };
  } catch {
    return null;
  }
}

function json(obj, status) {
  return new Response(JSON.stringify(obj), { status, headers: { "content-type": "application/json" } });
}
