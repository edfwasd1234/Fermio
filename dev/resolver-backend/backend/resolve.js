// Aggregation layer: given a title + season/episode, try a ranked list of
// sources and return the first that yields a directly-playable stream.
// Lets a native client (Fremio) resolve with fallbacks in a single request.

const wcotv = require("./wcotv");
const animegg = require("./animegg");
const animeheaven = require("./animeheaven");
const anizone = require("./anizone");
const hianime = require("./hianime");
const animekai = require("./animekai");
const anigo = require("./anigo");

const RESOLVERS = { wcotv, animegg, animeheaven, anizone, hianime, animekai, anigo };

// Sources that return a directly playable mp4/hls URL (AVPlayer-friendly),
// best-first. hianime is embed-only, kept out of the default set.
const DEFAULT_SOURCES = ["wcotv", "animegg", "animeheaven", "anizone"];

function norm(s) {
  return String(s || "").toLowerCase().replace(/[^a-z0-9]+/g, "");
}

function pickItem(items, title) {
  const t = norm(title);
  if (!t) return items[0];
  return (
    items.find((i) => norm(i.title) === t) ||
    items.find((i) => {
      const n = norm(i.title);
      return n && (n.includes(t) || t.includes(n));
    }) ||
    items[0]
  );
}

const JUNK = /deleted|extras?|special|trailer|preview|recap|behind|interview|\bost\b|\bpv\b|\bncop\b|\bnced\b/i;

// Season number encoded in an episode id, or null when unlabeled (unlabeled
// almost always means season 1 on these sites).
function seasonOf(id) {
  let m = String(id || "").match(/season[-\s]?0*(\d+)/i);
  if (m) return Number(m[1]);
  m = String(id || "").match(/s0*(\d+)e0*\d+/i);
  if (m) return Number(m[1]);
  return null;
}

function pickEpisode(eps, season, episode, dub, baseId = "") {
  if (!eps.length) return null;
  const epNum = Number(episode) || 1;
  const seasonNum = Number(season) || 1;
  const base = norm(baseId);

  // Drop non-canonical entries (deleted scenes, extras, specials…) unless
  // that's all there is.
  let pool = eps.filter((e) => !JUNK.test(e.id || ""));
  if (!pool.length) pool = eps;

  let candidates = pool.filter((e) => Number(e.number) === epNum);
  if (!candidates.length) candidates = pool;

  // Score each candidate: season fit + whether it's the main show (not a
  // spinoff whose id has extra tokens before "-season-/-episode-").
  const score = (e) => {
    const id = e.id || "";
    const s = seasonOf(id);
    let pts = 0;
    if (s === seasonNum) pts += 4;
    else if (seasonNum === 1 && s === null) pts += 2; // unlabeled ⇒ season 1
    const prefix = id.split(/-season-|-episode-/i)[0];
    if (base && norm(prefix) === base) pts += 2; // canonical, not a spinoff
    return pts;
  };

  const best = Math.max(...candidates.map(score));
  candidates = candidates.filter((e) => score(e) === best);

  // Positional safety net.
  if (!candidates.length) candidates = [pool[Math.min(epNum - 1, pool.length - 1)]];

  // Language preference among the best candidates.
  const wantDub = !!dub;
  const langed = candidates.filter((e) => {
    const isDub = /dub/i.test(String(e.duration || "") + " " + String(e.id || ""));
    return isDub === wantDub;
  });
  return (langed[0] || candidates[0]) ?? null;
}

async function resolveOne(src, { title, season, episode, dub }) {
  const resolver = RESOLVERS[src];
  if (!resolver) return { src, ok: false, reason: "unknown source" };
  try {
    const search = await resolver.search(title);
    const items = search?.items || [];
    if (!items.length) return { src, ok: false, reason: "no search results" };
    const item = pickItem(items, title);
    const eps = await resolver.episodes(item.id);
    if (!eps.length) return { src, ok: false, reason: "no episodes", matched: item.title };
    const ep = pickEpisode(eps, season, episode, dub, item.id);
    if (!ep) return { src, ok: false, reason: "no matching episode", matched: item.title };
    const streams = await resolver.streams(ep.id);
    if (!streams.length)
      return { src, ok: false, reason: "no streams", matched: item.title, episodeId: ep.id };
    return {
      src,
      ok: true,
      matched: item.title,
      episodeId: ep.id,
      episodeNumber: ep.number,
      language: /dub/i.test(String(ep.duration || "")) ? "Dubbed" : "Subbed",
      streams
    };
  } catch (error) {
    return { src, ok: false, reason: error instanceof Error ? error.message : String(error) };
  }
}

async function resolve({ title, season = 1, episode = 1, dub = false, sources }) {
  const order = (sources && sources.length ? sources : DEFAULT_SOURCES).filter((s) => RESOLVERS[s]);
  const tried = [];
  for (const src of order) {
    const r = await resolveOne(src, { title, season, episode, dub });
    if (r.ok) {
      return {
        ok: true,
        source: r.src,
        matched: r.matched,
        episodeId: r.episodeId,
        episodeNumber: r.episodeNumber,
        language: r.language,
        streams: r.streams,
        tried: [...tried, { src: r.src, ok: true }]
      };
    }
    tried.push({ src: r.src, ok: false, reason: r.reason });
  }
  return { ok: false, tried };
}

module.exports = { resolve, DEFAULT_SOURCES };
