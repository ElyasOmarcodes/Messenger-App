// Paigham push: the database calls this on every new message and ringing
// call (trigger push_notify, migration v11). It finds who should hear about
// it, their phones (push_tokens) and sends through Firebase Cloud Messaging
// (FCM HTTP v1; FCM also delivers to iPhones through APNs).
//
// Privacy: messages are end-to-end encrypted, so the push never carries the
// text — only who wrote and in which chat; the phone shows "new message".
//
// Secrets (supabase secrets set ...):
//   PUSH_SECRET           same value as push_config.secret in the database
//   FCM_SERVICE_ACCOUNT   the whole Firebase service-account JSON
// Provided by Supabase: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const sa = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "{}");
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

// ── Google OAuth token from the service account (RS256 JWT) ────────────────
let cached: { token: string; until: number } | null = null;

function b64url(data: ArrayBuffer | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : new Uint8Array(data);
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function accessToken(): Promise<string> {
  if (cached && cached.until > Date.now() + 60_000) return cached.token;
  const now = Math.floor(Date.now() / 1000);
  const head = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const pem = (sa.private_key as string).replace(/-----[^-]+-----/g, "").replace(/\s/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${head}.${claim}`));
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${head}.${claim}.${b64url(sig)}`,
  });
  const j = await res.json();
  if (!j.access_token) throw new Error(`Google sign-in failed: ${JSON.stringify(j).slice(0, 200)}`);
  cached = { token: j.access_token, until: Date.now() + (j.expires_in ?? 3600) * 1000 };
  return cached.token;
}

// texts shown on the phone, by the app's language
const T: Record<string, { msg: string; call: string; video: string }> = {
  ps: { msg: "نوی پیغام", call: "راتلونکی غږیز زنګ", video: "راتلونکی ویډیو زنګ" },
  fa: { msg: "پیام تازه", call: "تماس صوتی ورودی", video: "تماس تصویری ورودی" },
  en: { msg: "New message", call: "Incoming voice call", video: "Incoming video call" },
};

async function send(token: string, lang: string, title: string, body: string, data: Record<string, string>, call: boolean): Promise<string> {
  if (!sa.project_id || !sa.private_key) return "FCM_SERVICE_ACCOUNT missing or not valid JSON";
  let res: Response;
  try {
  res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
    method: "POST",
    headers: { Authorization: `Bearer ${await accessToken()}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      message: {
        token,
        // Android: data only, high priority — the app shows the notification
        // itself (in the user's language, a call as a full-screen ring)
        data: { ...data, title, body, lang },
        android: { priority: "HIGH", ttl: call ? "45s" : "86400s" },
        // iPhone: a normal alert (APNs), plus the data for the app
        apns: {
          headers: { "apns-priority": "10", "apns-push-type": "alert" },
          payload: { aps: { alert: { title, body }, sound: "default", "mutable-content": 1, "thread-id": data.chat_id } },
        },
      },
    }),
  });
  } catch (e) {
    return `error: ${e}`;
  }
  if (res.ok) return "sent";
  const e = await res.text();
  if ((res.status === 404 || res.status === 400) && (e.includes("UNREGISTERED") || e.includes("INVALID_ARGUMENT"))) {
    await db.from("push_tokens").delete().eq("token", token); // app removed / token stale
  }
  return `fcm ${res.status}: ${e.slice(0, 300)}`;
}

Deno.serve(async (req) => {
  if (req.headers.get("x-push-secret") !== Deno.env.get("PUSH_SECRET")) return new Response("no", { status: 401 });
  const { table, record } = await req.json();

  if (table === "messages") {
    const chatId = record.chat_id as string;
    const sender = record.sender_id as string;
    const [{ data: chat }, { data: members }, { data: who }] = await Promise.all([
      db.from("chats").select("is_group,title").eq("id", chatId).single(),
      db.from("chat_members").select("user_id,muted").eq("chat_id", chatId),
      db.from("profiles").select("display_name,email").eq("id", sender).single(),
    ]);
    const to = (members ?? []).filter((m) => m.user_id !== sender && !m.muted).map((m) => m.user_id);
    if (to.length === 0) return new Response("no recipients");
    const name = who?.display_name || (who?.email ?? "").split("@")[0];
    const { data: tokens } = await db.from("push_tokens").select("token,lang").in("user_id", to);
    if (!tokens?.length) return new Response(`no phones registered for ${to.length} recipient(s)`);
    const results = await Promise.all((tokens ?? []).map((t) => {
      const l = T[t.lang ?? "ps"] ?? T.ps;
      const title = chat?.is_group ? `${chat.title ?? ""} · ${name}` : name;
      return send(t.token, t.lang ?? "ps", title, l.msg, { type: "message", chat_id: chatId, message_id: record.id }, false);
    }));
    console.log("push message", results);
    return new Response(results.join("\n"));
  } else if (table === "calls") {
    const { data: who } = await db.from("profiles").select("display_name,email").eq("id", record.caller_id).single();
    const name = who?.display_name || (who?.email ?? "").split("@")[0];
    const { data: tokens } = await db.from("push_tokens").select("token,lang").eq("user_id", record.callee_id);
    await Promise.all((tokens ?? []).map((t) => {
      const l = T[t.lang ?? "ps"] ?? T.ps;
      return send(t.token, t.lang ?? "ps", name, record.video ? l.video : l.call,
        { type: "call", call_id: record.id, chat_id: record.chat_id, video: String(!!record.video) }, true);
    }));
  }
  return new Response("ok");
});
