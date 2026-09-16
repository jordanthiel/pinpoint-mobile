import { handle, roundRecapSchema, type Config } from "./handler.ts";
const config: Config = { key: "test-provider-key", supabaseURL: "http://auth.test", anonKey: "public-test-key" };
const assert = (value: unknown, label: string) => { if (!value) throw new Error(label); };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status });
const request = (body: unknown, headers = {}) => new Request("http://function.test", {
  method: "POST", headers: { Authorization: "Bearer valid-user", "Content-Type": "application/json", ...headers }, body: JSON.stringify(body),
});
function upstream(reply: unknown, calls: { url: string; init?: RequestInit }[] = []): typeof fetch {
  return (async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    calls.push({ url, init });
    if (url.endsWith("/auth/v1/user")) return json({ id: "golfer" });
    if (url.endsWith("/consume_golf_ai_request")) return json(true);
    return json(reply);
  }) as typeof fetch;
}
Deno.test("missing authentication never contacts OpenAI", async () => {
  const result = await handle(new Request("http://test", { method: "POST" }), config, (() => { throw Error("No network expected"); }) as typeof fetch);
  assert(result.status === 401, "401 required");
});
Deno.test("invalid session never contacts OpenAI", async () => {
  let count = 0;
  const result = await handle(request({ operation: "coach" }), config, (async () => { count++; return json({}, 401); }) as typeof fetch);
  assert(result.status === 401 && count === 1, "only auth check allowed");
});
Deno.test("missing provider key produces recoverable setup error", async () => {
  const calls: { url: string }[] = [];
  const result = await handle(request({}), { ...config, key: undefined }, upstream({}, calls));
  assert(result.status === 503 && calls.length === 1, "no paid request");
});
Deno.test("daily budget blocks paid requests", async () => {
  let count = 0;
  const result = await handle(request({}), config, (async () => json(++count === 1 ? { id: "golfer" } : false)) as typeof fetch);
  assert(result.status === 429 && count === 2, "quota enforced before OpenAI");
});
Deno.test("coach uses server-selected model, no storage and no client credentials", async () => {
  const calls: { url: string; init?: RequestInit }[] = [];
  const result = await handle(request({ operation: "coach", question: "How many holes?", evidence: "One scored hole", model: "untrusted-model", apiKey: "bad" }), config,
    upstream({ status: "completed", output: [{ content: [{ type: "output_text", text: "One scored hole." }] }] }, calls));
  const body = JSON.parse(calls[2].init?.body as string);
  assert(result.status === 200 && (await result.json()).text === "One scored hole.", "answer decoded");
  assert(body.model === "gpt-4.1-mini" && body.store === false, "server policy enforced");
  assert((calls[2].init?.headers as Record<string, string>).Authorization === "Bearer test-provider-key", "server key used");
});
Deno.test("recap rejects fabricated evidence quotes", async () => {
  const fabricated = { shots: [{ evidence: "Driver 300 yards" }], puttsMentioned: 1, scoreCall: "par" };
  const result = await handle(request({ operation: "recap", transcript: "par with one putt" }), config,
    upstream({ status: "completed", output: [{ content: [{ type: "output_text", text: JSON.stringify(fabricated) }] }] }));
  assert(result.status === 502, "unsupported shot rejected");
});
Deno.test("recap requests a strict schema and preserves summary-only holes", async () => {
  const recap = { shots: [], puttsMentioned: 1, scoreCall: "par" };
  const calls: { url: string; init?: RequestInit }[] = [];
  const result = await handle(request({ operation: "recap", transcript: "par with one putt" }), config,
    upstream({ status: "completed", output: [{ content: [{ type: "output_text", text: JSON.stringify(recap) }] }] }, calls));
  const body = JSON.parse(calls[2].init?.body as string);
  assert(result.status === 200 && (await result.json()).shots.length === 0, "no synthetic strokes");
  assert(body.text.format.strict === true && body.text.format.schema.additionalProperties === false, "strict schema");
});
Deno.test("truncated answers are never returned as complete", async () => {
  const result = await handle(request({ operation: "coach", question: "Why?", evidence: "One hole" }), config,
    upstream({ status: "incomplete", output: [{ content: [{ type: "output_text", text: "partial" }] }] }));
  assert(result.status === 502, "incomplete rejected");
});
Deno.test("audio uses multipart transcription endpoint and server model", async () => {
  const form = new FormData(); form.set("file", new File([new Uint8Array([1, 2, 3])], "test.m4a", { type: "audio/mp4" }));
  const calls: { url: string; init?: RequestInit }[] = [];
  const result = await handle(new Request("http://test", { method: "POST", headers: { Authorization: "Bearer valid-user" }, body: form }), config, upstream({ text: "Hole one, par." }, calls));
  assert(result.status === 200 && (await result.json()).text === "Hole one, par.", "transcript returned");
  assert(calls[2].url.endsWith("/audio/transcriptions"), "correct endpoint");
  assert((calls[2].init?.body as FormData).get("model") === "gpt-4o-transcribe", "correct model");
});
Deno.test("provider errors do not expose secrets or request content", async () => {
  let calls = 0;
  const result = await handle(request({ operation: "coach", question: "private question", evidence: "private data" }), config,
    (async () => ++calls === 1 ? json({ id: "golfer" }) : calls === 2 ? json(true) : json({ error: "test-provider-key private data" }, 500)) as typeof fetch);
  const text = await result.text();
  assert(result.status === 502 && !text.includes("test-provider-key") && !text.includes("private data"), "redacted error");
});

for (const [providerCode, status, expectedCode] of [
  ["insufficient_quota", 503, "provider_quota_exhausted"],
  ["billing_hard_limit_reached", 503, "provider_quota_exhausted"],
  ["rate_limit_exceeded", 429, "provider_rate_limited"],
] as const) {
  Deno.test(`provider ${providerCode} has an actionable safe error`, async () => {
    let calls = 0;
    const result = await handle(request({ operation: "recap", transcript: "par with two putts" }), config,
      (async () => ++calls === 1 ? json({ id: "golfer" }) : calls === 2 ? json(true) : json({ error: { code: providerCode, message: "private provider details" } }, 429)) as typeof fetch);
    const body = await result.json();
    assert(result.status === status && body.code === expectedCode, "quota and rate limits distinguished");
    assert(!JSON.stringify(body).includes("private provider details"), "provider details stay private");
    assert(calls === 3, "billing failures are not automatically retried");
  });
}

const roundTranscript = "On the first I used the big stick, caught the outer edge and peeled it into the right rough. The next one was a seven, flew it one forty. Actually that was hole two, and I made five with two putts. Back on one I had par with a single putt.";
const roundContext = { currentHole: 1, holes: [{ number: 1, par: 4 }, { number: 2, par: 4 }] };
function roundReply() {
  const shot = Object.fromEntries(Object.keys(roundRecapSchema.properties.holes.items.properties.shots.items.properties).map(k => [k, null]));
  Object.assign(shot, { evidence: roundTranscript, club: "driver", contact: "toe", shape: "fade", finish: "rough", lateralMiss: "right" });
  return { holes: [
    { holeNumber: 1, evidence: roundTranscript, score: 4, putts: 1, penalties: null, fairwayHit: null, scoreCall: "par", shots: [], notes: "", warnings: [] },
    { holeNumber: 2, evidence: roundTranscript, score: 5, putts: 2, penalties: null, fairwayHit: false, scoreCall: null, shots: [shot], notes: "Final hole correction applied.", warnings: [] },
  ], warnings: [] };
}
const completedRound = (reply: unknown) => ({ status: "completed", output: [{ content: [{ type: "output_text", text: JSON.stringify(reply) }] }] });
Deno.test("whole transcript and hole context go to the LLM once; returned interpretation is not reparsed", async () => {
  const calls: { url: string; init?: RequestInit }[] = [];
  const reply = roundReply();
  const result = await handle(request({ operation: "round_recap", transcript: roundTranscript, context: roundContext }), config, upstream(completedRound(reply), calls));
  assert(result.status === 200 && JSON.stringify(await result.json()) === JSON.stringify(reply), "model interpretation preserved exactly");
  const sent = JSON.parse(calls[2].init?.body as string);
  const input = JSON.parse(sent.input);
  assert(calls.length === 3 && input.transcript === roundTranscript && input.context.holes.length === 2, "one provider call, no regex segmentation");
  assert(sent.temperature === 0 && sent.text.format.strict && sent.store === false, "consistent structured output settings");
});
for (const invalid of ["unknown club", "out of range", "invented quote", "duplicate hole", "wrong hole", "missing field"]) {
  Deno.test(`round recap rejects ${invalid} without interpreting narration`, async () => {
    const reply: any = roundReply();
    if (invalid === "unknown club") reply.holes[1].shots[0].club = "magic club";
    if (invalid === "out of range") reply.holes[1].shots[0].carryYards = -10;
    if (invalid === "invented quote") reply.holes[1].shots[0].evidence = "I said nothing like this";
    if (invalid === "duplicate hole") reply.holes[1].holeNumber = 1;
    if (invalid === "wrong hole") reply.holes[1].holeNumber = 18;
    if (invalid === "missing field") delete reply.holes[0].putts;
    const result = await handle(request({ operation: "round_recap", transcript: roundTranscript, context: roundContext }), config, upstream(completedRound(reply)));
    assert(result.status === 502, "invalid model contract rejected");
  });
}
Deno.test("contradictory totals remain editable, not silently repaired", async () => {
  const reply = roundReply(); reply.holes[0].score = 2; reply.holes[0].putts = 3;
  const result = await handle(request({ operation: "round_recap", transcript: roundTranscript, context: roundContext }), config, upstream(completedRound(reply)));
  assert(result.status === 200 && (await result.json()).holes[0].putts === 3, "review retains stated values");
});
