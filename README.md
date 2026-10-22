# Ghost Town: invite page

This folder is the whole site. Requests go into a Supabase table that only you can see.

```
index.html              the page
img/                    photos, logos, grain texture, link-preview image (og.jpg)
audio/ghost-town.mp3    background track (loops; starts on the visitor's first tap)
supabase/schema.sql     the "requests" table and its insert-only rules
```

## 1. Where requests land

Supabase project **ghost-town**: https://supabase.com/dashboard/project/gwwiljdhsojlpdsqqxab

Open **Table Editor > requests**. Each request is one row: received, name, phone, instagram, referrer, status, notes.

- **status** starts as `Pending`. Change it to `Approved`, `Paid` or `Declined` by editing the cell.
- Filter or sort on any column; **Export > CSV** to open it in Google Sheets or Excel.
- Visitors can only add rows. They can't read, edit or delete anything (see `supabase/schema.sql`).

## 2. Connection

`index.html` holds the table URL and the project's publishable key (`INVITE_ENDPOINT`, `SUPABASE_KEY`). The publishable key is meant to be public; the table's rules are what keep the data private.

## 3. Put the site online

The page must be served from a real web address (`https://...`). Double-clicking `index.html` on your computer won't send requests.

**Easiest: Netlify Drop (free, about 1 minute)**
1. Go to https://app.netlify.com/drop
2. Drag this whole folder onto the page.
3. You get a live link straight away. Sign up for free to keep it, rename it, or attach your own domain (for example `ghosttown.jinxed.in`) under **Domain settings**.

Vercel, GitHub Pages, Cloudflare Pages or your own server work the same way: upload the folder as it is.

After it's live, edit the `og:image` line at the top of `index.html` to the full address of `img/og.jpg`, so WhatsApp and Instagram show the preview image. Then upload again.

## 4. Test it once

Open the live link on your phone, request an invite with your own details, and check that a new row appears in **Table Editor > requests**.

## If something goes wrong

- **"Your request didn't reach the house"** appears: open the browser console for the error, and check the project isn't paused in the Supabase dashboard (free projects pause after a week without traffic).
- **No music**: browsers block sound until the visitor taps something. The track starts on the first tap anywhere, and the button in the bottom-left corner mutes or unmutes it.

## A note on the music

The track is a commercial song. Playing it on a public website usually needs a licence from the rights holder, and Instagram can mute or take down content that uses it. If that's a concern, replace `audio/ghost-town.mp3` with a licensed or original track under the same file name.
