// Paigham TURN credentials: short-lived username/password for the coturn
// server (its "REST API" mode, use-auth-secret). Calls behind mobile carrier
// NAT (CGNAT) need a TURN relay; the password is valid for a few hours only,
// so it cannot be reused by others.
//
// Secrets: TURN_SECRET (= static-auth-secret in turnserver.conf)
//          TURN_URLS   e.g. "turn:turn.example.af:3478?transport=udp,turn:turn.example.af:3478?transport=tcp,turns:turn.example.af:5349"

import { createClient } from "npm:@supabase/supabase-js@2.45.4";

Deno.serve(async (req) => {
  // only signed-in users
  const auth = req.headers.get("Authorization") ?? "";
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: auth } },
  });
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return new Response("no", { status: 401 });

  const ttl = 6 * 3600;
  const username = `${Math.floor(Date.now() / 1000) + ttl}:${user.id}`;
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(Deno.env.get("TURN_SECRET")!), { name: "HMAC", hash: "SHA-1" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(username)));
  let s = "";
  for (const b of sig) s += String.fromCharCode(b);
  const credential = btoa(s);
  const urls = (Deno.env.get("TURN_URLS") ?? "").split(",").map((u) => u.trim()).filter(Boolean);
  return Response.json({ urls, username, credential, ttl });
});
