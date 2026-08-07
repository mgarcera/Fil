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
// Organizing a whole library into folders can emit many group→note lists, so allow more output.
const ORGANIZE_MAX_TOKENS = 2000;

const BUNDLE_ID = "com.masongarcera.Fil";
const PRODUCT_IDS = ["com.masongarcera.Fil.pro.monthly", "com.masongarcera.Fil.pro.annual"];
// Apple subscription status codes that grant entitlement: 1 = active, 4 = billing grace period.
const ENTITLED_STATUSES = [1, 4];
const APPSTORE_PROD = "https://api.storekit.itunes.apple.com";
const APPSTORE_SANDBOX = "https://api.storekit-sandbox.itunes.apple.com";

// Silent per-subscriber daily cap — a runaway/scripted guard, not a product limit. No human reaches
// it. The Anthropic account spend cap is the outer backstop.
const DAILY_LIMIT = 200;
// Haiku 4.5 pricing per token (USD): $1/MTok in, $5/MTok out, $0.10/MTok cache read.
const PRICE_IN = 1e-6, PRICE_OUT = 5e-6, PRICE_CACHE_READ = 0.1e-6;

const SYSTEM_PROMPT = `You help someone explore their own private notes (they call each one a "fil"). Each note is listed as:
  N. (when it was made, its type, whether it has open to-dos) title: snippet
Types are note, voice, link, photo.

Given a query and the list, do two things:

1. Return the notes that are genuinely about the query, best first, ordered by how well they fit. Be generous about what counts as "about it": a note fits if it is about the query, mentions it, or is a clear example of what the query asks for. For "app development links", that includes coding courses, developer tools, and framework or tutorial references, even if they don't say "app development" verbatim.

But stay anchored to the query's actual subject. Do NOT include a note just because it shares a broad area — don't return every tech or work note for a tech-sounding word. Include only notes a person would agree are really about this query.

If the query is about a feeling, mood, or kind of experience (for example "times i felt alive", "when i was anxious", "proud moments", "what excites me"), select the notes that capture or express that feeling or experience, even if they never name it. Read the emotional tone and what happened, not just the words. It's fine to include several. This kind of query is about resonance, not keywords.

Return an empty list only when nothing is genuinely about the query — a topic none of the notes actually cover, or a name or made-up word they never wrote about. Better to return nothing than a pile of loosely-related notes. (Do still include notes that are clearly about a real subject in the query, like coding/dev resources for "app development".)

If the query mentions a kind (photos, links, voice, to-dos) or a time (today, recently, older), use each note's (date, type, to-dos) tag to focus.

2. If you selected no notes, set "summary" to an empty string. Otherwise, reflect back what those selected notes are about, in a warm but grounded way, like a friend who listens well. 2 to 3 sentences, second person, in their voice. Stay close to what's actually written.

3. "suggestion": only when you return an EMPTY relevant list. Ask whether any of the notes are CLOSELY RELATED to what they searched for, just phrased differently, so a nearby search would surface them. If so, set "suggestion" to that short query (2 to 4 words, lowercase, the person's voice — e.g. searching "alive" when there are notes about a joyful trip could suggest "the trip"). It must be genuinely related to their query, not merely the most common topic in the notes. If nothing in the notes is closely related to what they searched for, set "suggestion" to an empty string (do not reach for a loose or generic match). Never repeat or lightly reword their original query. When you DO return notes, set "suggestion" to an empty string.

Voice rules:
- Warm but restrained. Never sentimental, flowery, or therapeutic. Do not psychoanalyze, infer hidden motives, or reach for deeper meaning the notes don't state.
- Describe what they've been noting about this, not who they are as a person.
- Never mention the search, the query, the matching, or that these notes are relevant. No "that's the direct hit on your query", "matching your search", "here's what came up", "which is exactly what you're asking about", "this is what you're looking for". Never affirm that a note answers them. Just describe what those selected notes say, and nothing beyond them.
- Lead with the content of the thought, not the container. Prefer "yesterday you were thinking about adding weeklite to rootcause" over "you've got a note about adding weeklite" or "you have a note from yesterday". Don't narrate that these are notes or fils; reflect the thinking itself.
- No clinical framing ("there's a tension between", "navigating with intention"), no advice, no nudges.
- Never use em dashes. Use commas, periods, or "and". Contractions welcome.
- Write in natural sentence case (the app handles lowercasing).

Respond with ONLY a JSON object, no prose or code fences:
{"summary": "...", "relevant": [numbers], "suggestion": "..."}`;

// Summarize-only mode: the app already chose the notes (a keyword match the model couldn't place
// semantically, e.g. an invented project name), and just needs a reflection of them.
const SUMMARIZE_PROMPT = `You help someone explore their own private notes (they call each one a "fil"). The notes below all came up for a search the person ran. Reflect back what they are about, in a warm but grounded way, like a friend who listens well. 2 to 3 sentences, second person, in their voice. Stay close to what's actually written.

Voice rules:
- Warm but restrained. Never sentimental, flowery, or therapeutic. Do not psychoanalyze, infer hidden motives, or reach for deeper meaning the notes don't state.
- Describe what they've been noting about this, not who they are as a person.
- Never mention the search, the query, the matching, or that these notes are relevant. Just describe what the notes say, and nothing beyond them.
- Lead with the content of the thought, not the container. Don't narrate that these are notes or fils; reflect the thinking itself.
- No clinical framing, no advice, no nudges.
- Never use em dashes. Use commas, periods, or "and". Contractions welcome.
- Write in natural sentence case (the app handles lowercasing).

Respond with ONLY the reflection text, no preamble, no quotes, no JSON.`;

// When the search was a time window ("this year", "last month", "3 days ago"), the person is looking
// back over that stretch — so the reflection should be situated in it and use retrospective voice.
function summarizeSystem(window) {
  if (!window) return SUMMARIZE_PROMPT;
  return SUMMARIZE_PROMPT + `\n\nThese notes are all from ${window}, a stretch of time the person is looking back on. Situate the reflection in that time and look back on it, for example "this year you kept coming back to..." or "that week was mostly about...". Use past or retrospective voice, never the present-tense "right now".`;
}

// Shared "user's voice" rules — the same restrained, grounded reflection voice the search summaries
// use. Reused for folder captions so every generated line sounds like Fil.
const VOICE_RULES = `Voice rules:
- Warm but restrained. Never sentimental, flowery, or therapeutic. Do not psychoanalyze, infer hidden motives, or reach for deeper meaning the notes don't state.
- Describe what the notes are about, not who the person is.
- Lead with the content of the thought, not the container. Don't narrate that these are notes or fils; reflect the thinking itself.
- No clinical framing, no advice, no nudges.
- Never use em dashes. Use commas, periods, or "and". Contractions welcome.
- Write in natural sentence case (the app handles lowercasing).`;

// Organize mode: group the whole library into a small set of TOPICAL folders (by subject, not mood).
const ORGANIZE_PROMPT = `You organize someone's private notes (they call each one a "fil") into a small set of folders by SUBJECT — what each note is about — the way a person files their own things: "Work", "Gift Ideas", "Recipes", "Apartment", "Reading".

Each note is listed as:
  N. (when it was made, its type, whether it has open to-dos) title: snippet

For each folder, provide:
- "name": one or two natural words in Title Case (e.g. "Work", "Gift Ideas", "Recipes"). No underscores, no punctuation, no numbering.
- "description": a single grounded sentence capturing what this folder holds, second person, in the person's voice. One sentence only, kept short.
- "fils": the numbers of the notes in this folder.

Rules:
- Create 3 to 8 folders. Prefer fewer, clearer folders over many tiny ones.
- Put every note in exactly one folder. Never leave a note out; if one truly fits nowhere, use a folder named "Misc".
- Group by topic/subject. Two notes that share a mood but are about different things belong in different folders.
- Base the folders on what's actually written; don't invent themes the notes don't support.

${VOICE_RULES}

Respond with ONLY a JSON object, no prose or code fences:
{"groups": [{"name": "Folder Name", "description": "...", "fils": [note numbers]}]}`;

export default {
  async fetch(request, env, ctx) {
    if (request.method !== "POST") return json({ error: "Use POST." }, 405);

    // Gate: verify an active Fil Pro subscription from the transaction id the app sends, and get the
    // stable originalTransactionId to attribute usage by.
    const transactionId = request.headers.get("X-Fil-Transaction-Id") || "";
    if (!transactionId) return json({ error: "Fil Pro is required to surface." }, 401);

    // Dev-only escape hatch: skip Apple verification so the local StoreKit config (fake purchases,
    // invisible to Apple's servers) can drive the full Pro flow while testing. Secure by default —
    // ONLY active when DEV_BYPASS is explicitly "1". Production never sets it, so verification is on.
    const bypassVerification = env.DEV_BYPASS === "1";

    let originalId;
    if (bypassVerification) {
      originalId = `dev:${transactionId}`;
    } else {
      try {
        originalId = await activeSubscriberId(transactionId, env);
      } catch (e) {
        return json({ error: "Couldn't verify your subscription." }, 502);
      }
      if (!originalId) return json({ error: "Fil Pro is required to surface." }, 403);
    }

    // Silent circuit-breaker: cap per-subscriber daily requests. Fails open on KV errors (the
    // Anthropic account spend cap is the hard backstop).
    const day = new Date().toISOString().slice(0, 10);
    try {
      const used = parseInt(await env.FIL_USAGE?.get(`count:${originalId}:${day}`), 10) || 0;
      if (used >= DAILY_LIMIT) return json({ error: "Daily surfacing limit reached. Try again tomorrow." }, 429);
    } catch { /* fail open */ }

    if (!env.ANTHROPIC_API_KEY) return json({ error: "Proxy is missing its Anthropic key." }, 500);

    let body;
    try {
      body = await request.json();
    } catch {
      return json({ error: "Body must be JSON." }, 400);
    }

    const query = typeof body.query === "string" ? body.query.trim() : "";
    const fils = Array.isArray(body.fils) ? body.fils : null;
    const organize = body.organize === true;
    if (!fils || (!organize && !query)) return json({ error: "Expected { query, fils: [...] }." }, 400);

    // Summarize-only mode: the app supplies the notes it already chose (a keyword match) and just wants
    // a reflection — no selection. Returns { summary } and never touches `relevant`.
    const summarizeOnly = body.summarize === true;
    const window = typeof body.window === "string" ? body.window.trim() : "";

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
      max_tokens: organize ? ORGANIZE_MAX_TOKENS : MAX_TOKENS,
      system: organize ? ORGANIZE_PROMPT : (summarizeOnly ? summarizeSystem(window) : SYSTEM_PROMPT),
      messages: [
        {
          role: "user",
          content: organize
            ? [{ type: "text", text: `Notes:\n${numbered}` }]
            : [
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
    const u = data.usage || {};
    const cost = costFromUsage(u);
    // Record usage after responding, so KV latency never delays the surfacing.
    ctx.waitUntil(recordUsage(env, originalId, day, cost));

    if (organize) {
      const groups = parseGroups(text);
      if (!groups) return json({ error: "Couldn't read the model's response." }, 502);
      console.log(`organize: ${fils.length} fils -> ${groups.length} folders | out ${u.output_tokens ?? 0} | $${cost.toFixed(5)}`);
      return json({ groups }, 200);
    }

    if (summarizeOnly) {
      console.log(`summarize "${query}": ${fils.length} fils | out ${u.output_tokens ?? 0} | $${cost.toFixed(5)}`);
      return json({ summary: text.trim(), relevant: [] }, 200);
    }

    const parsed = parseSurfacing(text);
    if (!parsed) return json({ error: "Couldn't read the model's response." }, 502);
    console.log(
      `surface "${query}": ${parsed.relevant.length} fils | in ${u.input_tokens ?? 0} out ${u.output_tokens ?? 0} cacheRead ${u.cache_read_input_tokens ?? 0} | $${cost.toFixed(5)}`,
    );

    return json({ summary: parsed.summary, relevant: parsed.relevant, suggestion: parsed.suggestion }, 200);
  },
};

/** Estimated USD cost of one Claude call from its token usage. */
function costFromUsage(u) {
  return (u.input_tokens ?? 0) * PRICE_IN
    + (u.output_tokens ?? 0) * PRICE_OUT
    + (u.cache_read_input_tokens ?? 0) * PRICE_CACHE_READ;
}

/** Best-effort per-subscriber attribution: bump today's request count and accumulate total cost. */
async function recordUsage(env, originalId, day, cost) {
  if (!env.FIL_USAGE) return;
  try {
    const countKey = `count:${originalId}:${day}`;
    const used = parseInt(await env.FIL_USAGE.get(countKey), 10) || 0;
    // ~2-day TTL so daily counters self-clean.
    await env.FIL_USAGE.put(countKey, String(used + 1), { expirationTtl: 60 * 60 * 48 });

    const costKey = `cost:${originalId}`;
    const prior = parseFloat(await env.FIL_USAGE.get(costKey)) || 0;
    await env.FIL_USAGE.put(costKey, (prior + cost).toFixed(6));
  } catch {
    /* best effort — attribution is protective, not critical */
  }
}

// MARK: - App Store subscription verification

/**
 * Ask Apple's App Store Server API for the subscription statuses tied to `transactionId` and return
 * the entitled subscriber's stable `originalTransactionId` (or null if none is active). Tries
 * production first, then sandbox.
 */
async function activeSubscriberId(transactionId, env) {
  const token = await appStoreAuthToken(env);
  for (const base of [APPSTORE_PROD, APPSTORE_SANDBOX]) {
    const res = await fetch(`${base}/inApps/v1/subscriptions/${encodeURIComponent(transactionId)}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (res.status === 404) continue; // unknown here — try the other environment
    if (!res.ok) continue;
    const id = entitledOriginalId(await res.json());
    if (id) return id;
  }
  return null;
}

function entitledOriginalId(payload) {
  for (const group of payload.data || []) {
    for (const tx of group.lastTransactions || []) {
      if (!ENTITLED_STATUSES.includes(tx.status)) continue;
      // The transaction info is a JWS from Apple (trusted TLS channel); read its payload to confirm
      // the product is one of ours, without needing to re-verify the signature.
      const info = decodeJWSPayload(tx.signedTransactionInfo);
      if (info && PRODUCT_IDS.includes(info.productId)) {
        return String(info.originalTransactionId || tx.originalTransactionId || info.transactionId);
      }
    }
  }
  return null;
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
    const suggestion = typeof obj.suggestion === "string" ? obj.suggestion : "";
    return { summary, relevant, suggestion };
  } catch {
    return null;
  }
}

/** Parse the organize-mode response: {"groups":[{name, fils:[numbers]}]}. */
function parseGroups(text) {
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start === -1 || end === -1 || end < start) return null;
  try {
    const obj = JSON.parse(text.slice(start, end + 1));
    if (!Array.isArray(obj.groups)) return null;
    return obj.groups
      .map((g) => ({
        name: typeof g.name === "string" ? g.name.trim() : "",
        description: firstSentence(g.description),
        fils: Array.isArray(g.fils) ? g.fils.filter((n) => Number.isInteger(n)) : [],
      }))
      .filter((g) => g.name && g.fils.length);
  } catch {
    return null;
  }
}

/** Clamp a caption to a single sentence, as a safety net over the prompt. */
function firstSentence(s) {
  if (typeof s !== "string") return "";
  const t = s.trim();
  const match = t.match(/^.*?[.!?](\s|$)/);
  return (match ? match[0] : t).trim();
}

function json(obj, status) {
  return new Response(JSON.stringify(obj), { status, headers: { "content-type": "application/json" } });
}
