// Emails a guest their Ghost Town pass. Called by the payments_email_pass trigger with { id }.
// Safe to call publicly: it only sends when the row is Paid, has an email, and hasn't been emailed yet,
// and it claims the row first so each pass goes out once.
// Secrets (Edge Functions > Secrets): RESEND_API_KEY, and optionally PASS_FROM (default below).
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import QRCode from "npm:qrcode@1.5.4";

const SITE = "https://jinxednetwork.github.io/ghost-town/";
const FROM = Deno.env.get("PASS_FROM") ?? "Ghost Town <passes@jinxednetwork.com>";
const REPLY_TO = "ian@jinxednetwork.com";
const CC = ["jinxed.net@gmail.com"]; // host copy of every pass
const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

// Names come from guests, so never trust them in HTML.
const esc = (s: string) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);

Deno.serve(async (req) => {
  const { id } = await req.json().catch(() => ({}));
  if (!Number.isInteger(id)) return Response.json({ error: "id required" }, { status: 400 });

  const { data: p, error } = await sb.from("payments")
    .update({ pass_emailed_at: new Date().toISOString(), pass_email_error: null })
    .eq("id", id).eq("status", "Paid").is("pass_emailed_at", null).not("email", "is", null)
    .select("code, name, email, passes, guests, pass_token").maybeSingle();
  if (error) return Response.json({ error: error.message }, { status: 500 });
  if (!p) return Response.json({ sent: false });

  const link = SITE + "pass.html#" + p.pass_token;
  const fail = async (msg: string) => {
    await sb.from("payments").update({ pass_email_error: msg.slice(0, 500) }).eq("id", id);
    return Response.json({ sent: false, error: msg }, { status: 502 });
  };
  const key = Deno.env.get("RESEND_API_KEY");
  if (!key) return fail("RESEND_API_KEY not set");

  const qr = (await QRCode.toDataURL(link, { width: 480, margin: 2, errorCorrectionLevel: "M" })).split(",")[1];
  const guests = (p.guests ?? []).map((g: { name: string }) => g.name).filter(Boolean);
  const html = `<!doctype html><html><body style="margin:0;background:#070707;color:#ece8e1;font-family:Georgia,serif">
<div style="max-width:440px;margin:0 auto;padding:32px 20px;text-align:center">
  <div style="font-size:44px;line-height:1">Ghost Town</div>
  <div style="margin-top:8px;font:12px monospace;letter-spacing:3px;color:#a39d94">FRI 30 OCT &middot; DUSK TILL MIDNIGHT</div>
  <div style="margin-top:26px;border:2px dashed #c8241a;padding:22px 16px">
    <div style="font:bold 14px monospace;letter-spacing:4px;color:#e2352a">ADMIT ${p.passes}</div>
    <img src="cid:pass-qr" width="240" height="240" alt="Entry QR" style="display:block;margin:16px auto;background:#fff">
    <div style="font:bold 34px monospace">${esc(p.code)}</div>
    <div style="margin-top:6px;font-size:22px">${esc(p.name)}</div>
    ${guests.length ? `<div style="margin-top:4px;font-style:italic;color:#d6d1c9">with ${guests.map(esc).join(", ")}</div>` : ""}
    <p style="margin:16px 0 0;font-style:italic;color:#a39d94">Show this QR at the door with photo ID. Costume compulsory.</p>
  </div>
  <a href="${link}" style="display:block;margin-top:16px;padding:16px;background:#c8241a;color:#ece8e1;text-decoration:none;font:bold 13px monospace;letter-spacing:3px">OPEN YOUR PASS</a>
  <p style="margin-top:22px;font-size:15px;color:#a39d94">Trouble? WhatsApp or call +91 98191 96888, or reply to this email.</p>
</div></body></html>`;

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: "Bearer " + key, "Content-Type": "application/json" },
    body: JSON.stringify({
      from: FROM, to: [p.email], cc: CC, reply_to: REPLY_TO,
      subject: `Your Ghost Town pass · ${p.code} · Admit ${p.passes}`,
      html,
      text: `Ghost Town, Fri 30 Oct. Admit ${p.passes}. ${p.code}, ${p.name}.\nYour pass: ${link}\nShow the QR at the door with photo ID.`,
      attachments: [{ filename: "ghost-town-pass.png", content: qr, content_id: "pass-qr" }],
    }),
  });
  if (!res.ok) return fail("Resend " + res.status + ": " + (await res.text()));
  return Response.json({ sent: true });
});
