# Ghost Town: invite page

This folder is the whole site. Requests go into a Google Sheet that only you can see.

```
index.html              the page
img/                    photos, logos, grain texture, link-preview image (og.jpg)
audio/ghost-town.mp3    background track (loops; starts on the visitor's first tap)
google-sheet/Code.gs    the script that writes each request into your Sheet
```

## 1. Set up the Google Sheet (about 5 minutes)

1. Create a new Google Sheet, for example "Ghost Town: Requests".
2. In the Sheet, open **Extensions > Apps Script**.
3. Delete what's in the editor, paste in everything from `google-sheet/Code.gs`, and press **Save**.
4. Click **Deploy > New deployment**. Next to "Select type", click the gear and choose **Web app**.
   - Execute as: **Me**
   - Who has access: **Anyone**
5. Click **Deploy**, then sign in and allow access when Google asks. You'll see a warning that the app isn't verified. That's expected for your own script: click **Advanced > Go to project**.
6. Copy the **Web app URL**. It ends in `/exec`.
7. Paste that URL into your browser. You should see `{"ok":true,"message":"Ghost Town request endpoint is live."}`.

## 2. Connect the page to the Sheet

Open `index.html` in a text editor. Find this line near the bottom:

```js
const INVITE_ENDPOINT = "";
```

Paste your Web app URL between the quotes, then save the file:

```js
const INVITE_ENDPOINT = "https://script.google.com/macros/s/XXXXXXXX/exec";
```

## 3. Put the site online

The page must be served from a real web address (`https://...`). Double-clicking `index.html` on your computer won't send requests.

**Easiest: Netlify Drop (free, about 1 minute)**
1. Go to https://app.netlify.com/drop
2. Drag this whole folder onto the page.
3. You get a live link straight away. Sign up for free to keep it, rename it, or attach your own domain (for example `ghosttown.jinxed.in`) under **Domain settings**.

Vercel, GitHub Pages, Cloudflare Pages or your own server work the same way: upload the folder as it is.

After it's live, edit the `og:image` line at the top of `index.html` to the full address of `img/og.jpg`, so WhatsApp and Instagram show the preview image. Then upload again.

## 4. Test it once

Open your live link on your phone, request an invite with your own details, and check that a new row appears in the **Requests** tab of the Sheet within a few seconds.

## 5. Reviewing requests

Each request lands as one row:

| Received | Name | Phone | Instagram | Who sent them | Status | Notes |
|---|---|---|---|---|---|---|

- **Status** starts as `Pending` and has a dropdown: `Approved`, `Paid`, `Declined`.
- Approve someone by changing their status, then send them the payment link on WhatsApp.
- To get an email whenever a request arrives, open **Tools > Notification settings > Edit notifications** in the Sheet and choose "Any changes are made".
- Filter on Status to see who's still waiting.

## Changing the script later

If you edit `Code.gs`, use **Deploy > Manage deployments > Edit (pencil) > Version: New version > Deploy**. The URL stays the same, so the page doesn't need changing.

## If something goes wrong

- **"Your request didn't reach the house"** appears: check that the URL in `INVITE_ENDPOINT` ends in `/exec`, and that the deployment's access is set to **Anyone**.
- **No new row appears**: in Apps Script, open **Executions** on the left to see the error.
- **No music**: browsers block sound until the visitor taps something. The track starts on the first tap anywhere, and the button in the bottom-left corner mutes or unmutes it. On an iPhone, the silent switch also mutes it.

## A note on the music

The track is a commercial song. Playing it on a public website usually needs a licence from the rights holder, and Instagram can mute or take down content that uses it. If that's a concern, replace `audio/ghost-town.mp3` with a licensed or original track under the same file name.
