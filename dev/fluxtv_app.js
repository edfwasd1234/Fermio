(function () {
  'use strict';

  const ENDPOINT = 'https://xrjs-2026.hf.space/heartbeat';
  const INTERVAL = 30_000;

  const SESSION = (function () {
    try {
      let id = sessionStorage.getItem('_ftv_sid');
      if (!id) { id = crypto.randomUUID(); sessionStorage.setItem('_ftv_sid', id); }
      return id;
    } catch (_) { return crypto.randomUUID(); }
  })();

  let lastMediaKey = null;
  let pingTimer    = null;

  function parseHash() {
    const hash = window.location.hash || '#/';
    const movieMatch = hash.match(/^\#\/movie\/(\d+)/);
    if (movieMatch) return { page: 'watch', media_type: 'movie', media_id: parseInt(movieMatch[1], 10), season: null, episode: null };
    const tvMatch = hash.match(/^\#\/tv\/(\d+)\/(\d+)\/(\d+)/);
    if (tvMatch) return { page: 'watch', media_type: 'tv', media_id: parseInt(tvMatch[1], 10), season: parseInt(tvMatch[2], 10), episode: parseInt(tvMatch[3], 10) };
    return { page: 'home', media_type: null, media_id: null, season: null, episode: null };
  }

  function mediaKey(s) { return `${s.media_type}:${s.media_id}:${s.season}:${s.episode}`; }

  async function ping(isNewView) {
    const state = parseHash();
    try {
      await fetch(ENDPOINT, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ session_id: SESSION, page: state.page, media_type: state.media_type, media_id: state.media_id, season: state.season, episode: state.episode, is_new_view: !!isNewView }),
        keepalive: true,
      });
    } catch (_) {}
  }

  function schedulePing() { clearInterval(pingTimer); pingTimer = setInterval(function () { ping(false); }, INTERVAL); }

  function onHashChange() {
    const state = parseHash();
    const key = mediaKey(state);
    const isNew = state.page === 'watch' && key !== lastMediaKey;
    lastMediaKey = key;
    ping(isNew);
    schedulePing();
  }

  const initState = parseHash();
  lastMediaKey = mediaKey(initState);
  ping(initState.page === 'watch');
  schedulePing();

  window.addEventListener('hashchange', onHashChange);
})();