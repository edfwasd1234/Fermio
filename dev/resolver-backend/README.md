# Fremio resolver backend (vendored)

Server 3 (anime & cartoons) in the Fremio app resolves streams through this
backend instead of natively, because WCO.tv's `getvidlink.php` is now behind
Cloudflare and native iOS `URLSession` can't pass the challenge (it's gated by
TLS/client fingerprint). The backend shells out to `curl`, which does.

This is a **vendored snapshot** of the resolver from
[edfwasd1234/FerAnimeNative](https://github.com/edfwasd1234/FerAnimeNative)
(`backend/`), the source of truth. The `/api/resolve` aggregation endpoint was
added in FerAnimeNative PR #1.

## Run it

Dependency-free — only Node built-ins plus the `curl` binary on PATH.

```bash
node dev/resolver-backend/backend/server.js
# → FerAnime resolver listening on http://localhost:4517
```

Set a different port with `PORT=xxxx`. It binds `0.0.0.0`, so the phone can
reach it on the LAN at `http://<this-machine-ip>:4517`.

Then in the app: **Settings → Streaming Backend → Resolver URL** =
`http://<this-machine-ip>:4517`

## The endpoint the app calls

```
GET /api/resolve?title=<t>&season=<s>&episode=<e>&dub=<0|1>&sources=<csv>
```

Tries a ranked list of sources (default `wcotv,animegg,animeheaven,anizone`)
and returns the first that yields a directly-playable mp4/hls stream:

```json
{
  "ok": true,
  "source": "wcotv",
  "matched": "Rick and Morty",
  "episodeId": "rick-and-morty-episode-1-pilot",
  "language": "Subbed",
  "streams": [
    { "quality": "1080p", "type": "mp4", "url": "https://neptun.wcostream.com/getvid?evid=…",
      "headers": { "Referer": "https://embed.wcostream.com/…" } }
  ],
  "tried": [{ "src": "wcotv", "ok": true }]
}
```

## Working sources (verified)

| Source | Type | Notes |
|--------|------|-------|
| wcotv | mp4 | cartoons + anime |
| animegg | mp4 | anime |
| animeheaven | mp4 | anime |
| anizone | hls | anime |
| hianime | embed | iframe only — not directly playable, excluded from default |
| animekai, anigo | — | search currently broken upstream |

## Hosting for real

For a permanent, internet-reachable resolver (no LAN dependency, HTTPS so no iOS
ATS exception needed), deploy FerAnimeNative to Railway or Render (their configs
are in that repo). `curl` is present on those container hosts. Vercel won't work
— serverless has no `curl`/`child_process`.
