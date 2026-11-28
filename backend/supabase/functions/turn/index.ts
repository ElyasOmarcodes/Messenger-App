// Paigham TURN credentials. Calls over mobile data (carrier NAT / CGNAT) and
// strict Wi-Fi often connect and then drop, or never connect, without a TURN
// relay. This function hands a signed-in user short-lived relay passwords.
//
// Use ONE of these (Supabase → Edge Functions → Secrets):
//
//  A) Cloudflare TURN (easiest; generous free tier, servers near Afghanistan):
//       CF_TURN_KEY_ID      the "Turn Token ID"
//       CF_TURN_API_TOKEN   its "API Token"
//
//  B) Metered (free plan, no bank card): METERED_DOMAIN (e.g. paigham.metered.live)
//       and METERED_API_KEY
//
//  C) Your own coturn server (use-auth-secret mode, see backend/turn/):
//       TURN_SECRET  = static-auth-secret in turnserver.conf
//       TURN_URLS    e.g. "turn:turn.example.af:3478?transport=udp,turn:turn.example.af:3478?transport=tcp"
//
// Answer: { ice_servers: [...], ttl } (and, for old app versions, urls /
// username / credential of the first relay).

import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

type Ice = { urls: string | string[]; username?: string; credential?: string };

async function cloudflare(ttl: number): Promise<Ice[] | null> {
  const id = Deno.env.get("CF_TURN_KEY_ID"), token = Deno.env.get("CF_TURN_API_TOKEN");
  if (!id || !token) return null;
  const res = await fetch(`https://rtc.live.cloudflare.com/v1/turn/keys/${id}/credentials/generate-ice-servers`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ ttl }),
  });
  if (!res.ok) throw new Error(`cloudflare ${res.status}: ${(await res.text()).slice(0, 200)}`);
  const j = await res.json();
  const list = Array.isArray(j.iceServers) ? j.iceServers : [j.iceServers];
  return list.filter(Boolean);
}

// Metered (metered.ca): a free plan without a bank card
async function metered(): Promise<Ice[] | null> {
  const domain = Deno.env.get("METERED_DOMAIN"), key = Deno.env.get("METERED_API_KEY");
  if (!domain || !key) return null;
  const host = domain.replace(/^https?:\/\//, "").replace(/\/.*$/, "");
  const res = await fetch(`https://${host}/api/v1/turn/credentials?apiKey=${encodeURIComponent(key)}`);
  if (!res.ok) throw new Error(`metered ${res.status}: ${(await res.text()).slice(0, 200)}`);
  const j = await res.json();
  return Array.isArray(j) ? j : (j.iceServers ?? []);
}

// A fixed relay login (e.g. a Metered credential): TURN_URLS, TURN_USERNAME, TURN_CREDENTIAL
function fixed(): Ice[] | null {
  const user = Deno.env.get("TURN_USERNAME"), pass = Deno.env.get("TURN_CREDENTIAL");
  const urls = (Deno.env.get("TURN_URLS") ?? "").split(",").map((u) => u.trim()).filter(Boolean);
  if (!user || !pass || urls.length === 0) return null;
  return [{ urls, username: user, credential: pass }];
}

async function coturn(userId: string, ttl: number): Promise<Ice[] | null> {
  const secret = Deno.env.get("TURN_SECRET");
  const urls = (Deno.env.get("TURN_URLS") ?? "").split(",").map((u) => u.trim()).filter(Boolean);
  if (!secret || urls.length === 0) return null;
  const username = `${Math.floor(Date.now() / 1000) + ttl}:${userId}`;
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-1" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(username)));
  let s = "";
  for (const b of sig) s += String.fromCharCode(b);
  return [{ urls, username, credential: btoa(s) }];
}

Deno.serve(async (req) => {
  // only signed-in users
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: { user } } = await db.auth.getUser(token);
  if (!user) return new Response("no", { status: 401 });

  const ttl = 6 * 3600;
  try {
    const ice = (await cloudflare(ttl)) ?? (await metered()) ?? fixed() ?? (await coturn(user.id, ttl)) ?? [];
    const relay = ice.find((s) => s.username);
    return Response.json({
      ice_servers: ice,
      ttl,
      urls: relay ? (Array.isArray(relay.urls) ? relay.urls : [relay.urls]) : [],
      username: relay?.username,
      credential: relay?.credential,
    });
  } catch (e) {
    console.error(e);
    return Response.json({ ice_servers: [], ttl: 300, urls: [], error: String(e) });
  }
});
