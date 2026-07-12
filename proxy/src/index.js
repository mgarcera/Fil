/**
 * Fil surfacing proxy — Cloudflare Worker (phase 1 MVP).
 *
 * Holds the Anthropic API key server-side so it never ships in the app. Given a query + the user's
 * fils, it asks Claude (Haiku) to pick the genuinely relevant ones and write a short synthesis, then
 * returns { summary, relevant: [numbers] } to the client.
 *
 * MVP scope: NO subscription check yet (phase 4). Access is gated only by a shared-secret header so
 * the endpoint isn't fully open. A shared secret embedded in the app is extractable, so this is a
 * stopgap — App Attest / StoreKit verification replaces it before launch.
 *
 * Secrets (set with `wrangler secret put`, never committed):
 *   ANTHROPIC_API_KEY    — the Anthropic key
 *   PROXY_SHARED_SECRET  — matched against the client's X-Fil-Proxy-Key header
 */

const MODEL = "claude-haiku-4-5";
const ANTHROPIC_ENDPOINT = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";
const MAX_TOKENS = 800;

// The surfacing system prompt lives here (not in the app) so it can be tuned without an App Store
// update. Keep the voice rules in sync with the /fil-voice skill.
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
    if (request.method !== "POST") {
      return json({ error: "Use POST." }, 405);
    }

    // Shared-secret gate (MVP stopgap; replaced by subscription verification in phase 4).
    const provided = request.headers.get("X-Fil-Proxy-Key") || "";
    if (!env.PROXY_SHARED_SECRET || provided !== env.PROXY_SHARED_SECRET) {
      return json({ error: "Unauthorized." }, 401);
    }

    if (!env.ANTHROPIC_API_KEY) {
      return json({ error: "Proxy is missing its Anthropic key." }, 500);
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return json({ error: "Body must be JSON." }, 400);
    }

    const query = typeof body.query === "string" ? body.query.trim() : "";
    const fils = Array.isArray(body.fils) ? body.fils : null;
    if (!query || !fils) {
      return json({ error: "Expected { query, fils: [...] }." }, 400);
    }

    // Rebuild the numbered corpus the client used to build itself.
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
            // Cache the stable corpus prefix; the query trails after so repeat queries read the
            // corpus at 0.1x (once it clears Haiku's 4,096-token minimum).
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
    } catch (e) {
      return json({ error: "Could not reach the model." }, 502);
    }

    if (!upstream.ok) {
      const detail = (await upstream.text()).slice(0, 200);
      return json({ error: `Model request failed (${upstream.status}). ${detail}` }, 502);
    }

    const data = await upstream.json();
    const text = (data.content || []).find((b) => b.type === "text")?.text || "";
    const parsed = parseSurfacing(text);
    if (!parsed) {
      return json({ error: "Couldn't read the model's response." }, 502);
    }

    // Cost/usage log (phase 4 turns this into per-user attribution in KV).
    const u = data.usage || {};
    console.log(
      `surface "${query}": ${parsed.relevant.length} fils | in ${u.input_tokens ?? 0} out ${u.output_tokens ?? 0} cacheWrite ${u.cache_creation_input_tokens ?? 0} cacheRead ${u.cache_read_input_tokens ?? 0}`,
    );

    return json({ summary: parsed.summary, relevant: parsed.relevant }, 200);
  },
};

/** Extract the {"summary","relevant"} object, tolerating stray wrapping/code fences. */
function parseSurfacing(text) {
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start === -1 || end === -1 || end < start) return null;
  try {
    const obj = JSON.parse(text.slice(start, end + 1));
    const summary = typeof obj.summary === "string" ? obj.summary : "";
    const relevant = Array.isArray(obj.relevant)
      ? obj.relevant.filter((n) => Number.isInteger(n))
      : [];
    return { summary, relevant };
  } catch {
    return null;
  }
}

function json(obj, status) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json" },
  });
}
