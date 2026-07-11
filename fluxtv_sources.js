/* ── SOURCES CONFIG ──
   Single source of truth for embed/server sources.
   - Add, remove, or reorder entries here; the server dropdown (player picker
     + settings fallback) and all internal lookups rebuild from this array,
     so nothing else needs to change.
   - `id`      : internal key, used in localStorage, URLs (?server=) and routing.
   - `name`    : display name shown in the picker (e.g. "Flux 1").
   - `desc`    : short descriptor shown under the name in the dropdown.
   - `sandbox` : true if the embed should be loaded in a sandboxed iframe
                 (allow-scripts allow-same-origin allow-forms allow-presentation
                 allow-pointer-lock). Use true for sources you trust enough to
                 restrict-but-allow; false removes the sandbox attribute entirely.
   - `movie(id)`        : returns the embed URL for a movie.
   - `tv(id, s, e)`      : returns the embed URL for a TV episode (season s, episode e).
*/
const SOURCES_LIST = [
  {
    id: 'flux1',
    name: 'Flux 1',
    desc: 'no ads · glitchy · subs',
    sandbox: true,
    movie: id => `https://vaplayer.ru/embed/movie/${id}?skin=netflix&color=e50914&title=false&autoplay=0`,
    tv: (id, s, e) => `https://vaplayer.ru/embed/tv/${id}/${s}/${e}?skin=netflix&color=e50914&title=false&autoplay=0`,
  },
  {
    id: 'flux2',
    name: 'Flux 2',
    desc: 'no ads · nice ui · subs',
    sandbox: true,
    movie: id => `https://z.zxcstream.xyz/embed/movie/${id}`,
    tv: (id, s, e) => `https://z.zxcstream.xyz/embed/tv/${id}/${s}/${e}`,
  },
  {
    id: 'flux3',
    name: 'Flux 3',
    desc: 'no ads · good · subs',
    sandbox: true,
    movie: id => `https://embed.filmu.in/movie/${id}`,
    tv: (id, s, e) => `https://embed.filmu.in/tv/${id}/${s}/${e}`,
  },
  {
    id: 'vares',
    name: 'Vares',
    desc: 'ads · fastest · subs',
    sandbox: false,
    movie: id => `https://vares.top/movie/${id}`,
    tv: (id, s, e) => `https://vares.top/tv/${id}/${s}/${e}`,
  },
  {
    id: 'november',
    name: 'November',
    desc: 'ads · most reliable · subs',
    sandbox: false,
    movie: id => `https://vidfast.me/movie/${id}?autoPlay=false&theme=E50914`,
    tv: (id, s, e) => `https://vidfast.me/tv/${id}/${s}/${e}?autoPlay=false&nextButton=true&autoNext=true&theme=E50914`,
  },
];
/* ── DERIVED LOOKUPS (do not edit below — generated from SOURCES_LIST) ── */
// Object form keyed by id, e.g. SOURCES.flux1.movie(id)  — preserves the
// exact shape the rest of the app already expects.
const SOURCES = Object.fromEntries(
  SOURCES_LIST.map(s => [s.id, { movie: s.movie, tv: s.tv, sandbox: s.sandbox }])
);
// id -> display name, e.g. SOURCE_NAMES.flux1 === 'Flux 1'
const SOURCE_NAMES = Object.fromEntries(SOURCES_LIST.map(s => [s.id, s.name]));
// The default/fallback source id is simply the first entry in the list.
const DEFAULT_SOURCE_ID = SOURCES_LIST[0].id;