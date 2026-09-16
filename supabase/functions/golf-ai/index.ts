import { handle } from "./handler.ts";
Deno.serve((request) => handle(request, {
  key: Deno.env.get("OPENAI_API_KEY"),
  supabaseURL: Deno.env.get("SUPABASE_URL") ?? "",
  anonKey: Deno.env.get("SUPABASE_ANON_KEY") ?? "",
  textModel: Deno.env.get("OPENAI_TEXT_MODEL"),
  transcriptionModel: Deno.env.get("OPENAI_TRANSCRIPTION_MODEL"),
}));
