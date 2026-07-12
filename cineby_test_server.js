const http = require('http');
const https = require('https');
const url = require('url');

// Decryption Key and Magic Headers
const u = [1116352408, 1899447441, 3049323471, 3921009573, 961987163, 1508970993, 2453635748, 2870763221, 3624381080, 310598401, 607225278, 1426881987, 1925078388, 2162078206, 2614888103, 3248222580];
const l = [109, 118, 109, 49]; // "mvm1"
const c_func = e => (e * (e + 1) & 1) == 0;
const s_func = e => (e * (e + 1) & 1) == 1;

function f(e) {
  e >>>= 0;
  e ^= e >>> 16;
  e = Math.imul(e, 2246822507) >>> 0;
  e ^= e >>> 13;
  e = Math.imul(e, 3266489909) >>> 0;
  return (e ^= e >>> 16) >>> 0;
}

function d(e, t) {
  return (e >>>= 0, 0 == (t &= 31)) ? e >>> 0 : (e << t | e >>> 32 - t) >>> 0;
}

function fnv1a(str) {
  let hash = 2166136261;
  const bytes = Buffer.from(str, 'utf8');
  for (let i = 0; i < bytes.length; i++) {
    hash = Math.imul(hash ^ bytes[i], 16777619) >>> 0;
  }
  return f(hash);
}

// Decrypt Cipher
function decrypt(encryptedBase64, seed, mediaId) {
  const data = Buffer.from(encryptedBase64.replace(/-/g, "+").replace(/_/g, "/"), 'base64');
  const length = data.length;

  const seedLen = seed.length;
  let o, acc;

  if (s_func(seedLen)) {
    const t = Array(256);
    for (let e = 0; e < 256; e++) t[e] = e;
    let r = 0;
    const seedCodes = Array.from(seed).map(c => c.charCodeAt(0));
    for (let n = 0; n < 256; n++) {
      r = (r + t[n] + seedCodes[n % seedCodes.length]) & 255;
      let o = t[n];
      t[n] = t[r];
      t[r] = o;
    }
    o = t;

    let tempAcc = 1732584193;
    for (let r = 0; r < seed.length; r++) {
      tempAcc = d((tempAcc ^ Math.imul(seed.charCodeAt(r), u[15 & r])) >>> 0, 5);
    }
    acc = f(tempAcc);
  } else {
    const r = Array(61);
    const fnvHash = fnv1a(seed);
    const idHash = f((mediaId >>> 0) ^ 2654435769);
    let n = f(fnvHash ^ idHash);

    for (let e = 0; e < 8; e++) {
      if (c_func(e)) {
        let t = n % 61;
        n = d(n + 2654435769 >>> 0, 7 + (7 & e));
        r[t] = (n ^ f(n)) >>> 0;
        n = f(n + t >>> 0);
      } else {
        r[e] = u[15 & e];
      }
    }
    o = r;
    acc = f(2779096485 ^ n);
  }

  const keyStream = new Uint8Array(length);
  let aIndex = 0;
  let byteIndex = 0;

  function nextKeyStreamByte() {
    const i = acc % 61;
    const isSet = i in o;
    const uVal = 0 - Number(isSet);
    const lVal = o[i] >>> 0;

    const r = acc;
    const n = (lVal ^ Math.imul(2654435769, aIndex + 1) >>> 0) >>> 0;
    let c = (r ^ n) | (r & n & uVal) >>> 0;
    c = (d(c + acc >>> 0, 31 & i) ^ d(acc, 31 & Math.imul(i, 7))) >>> 0;
    acc = f(c + 2654435769 >>> 0);
    o[i] = acc >>> 0;
    aIndex++;
    return acc;
  }

  while (byteIndex < length) {
    const keyWord = nextKeyStreamByte();
    keyStream[byteIndex++] = keyWord & 255;
    if (byteIndex < length) keyStream[byteIndex++] = (keyWord >> 8) & 255;
    if (byteIndex < length) keyStream[byteIndex++] = (keyWord >> 16) & 255;
    if (byteIndex < length) keyStream[byteIndex++] = (keyWord >> 24) & 255;
  }

  const decryptedBytes = new Uint8Array(length);
  for (let i = 0; i < length; i++) {
    decryptedBytes[i] = data[i] ^ keyStream[i];
  }

  for (let i = 0; i < l.length; i++) {
    if (decryptedBytes[i] !== l[i]) {
      throw new Error("Keystream check failed: magic prefix mismatch");
    }
  }

  return Buffer.from(decryptedBytes.subarray(l.length)).toString('utf8');
}

function l_shuffle(e, t) {
    let r;
    if (0 === t.length) return e;
    let i = [...e];
    for (let e = i.length - 1, s = 0, o = 0; e > 0; e--, s++) {
        s %= t.length;
        o += r = t[s].charCodeAt(0);
        let a = (r + s + o) % e;
        let n = i[e], l = i[a];
        i[a] = n;
        i[e] = l;
    }
    return i;
}

function d_encode(e, t) {
    let r = [], i = e;
    do r.unshift(t[i % t.length]), i = Math.floor(i / t.length); while (i > 0);
    return r;
}

function p_split(e, t, r) {
    return Array.from({ length: Math.ceil(e.length / t) }, (i, s) => r(e.slice(s * t, (s + 1) * t)));
}

// Hashids implementation for token generation
class Hashids {
    constructor(e = "", t = 0, r = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890", a = "cfhistuCFHISTU") {
        this.minLength = t;
        this.salt = Array.from(e);
        let p = [...new Set(r)];
        this.alphabet = p.filter(e => !a.includes(e));
        let m = a.split("").filter(e => p.includes(e));
        this.seps = l_shuffle(m, this.salt);
        if (this.seps.length === 0 || this.alphabet.length / this.seps.length > 3.5) {
            let e = Math.ceil(this.alphabet.length / 3.5);
            if (e > this.seps.length) {
                let t = e - this.seps.length;
                this.seps.push(...this.alphabet.slice(0, t));
                this.alphabet = this.alphabet.slice(t);
            }
        }
        this.alphabet = l_shuffle(this.alphabet, this.salt);
        let b = Math.ceil(this.alphabet.length / 12);
        if (this.alphabet.length < 3) {
            this.guards = this.seps.slice(0, b);
            this.seps = this.seps.slice(b);
        } else {
            this.guards = this.alphabet.slice(0, b);
            this.alphabet = this.alphabet.slice(b);
        }
    }
    
    encode(e, ...t) {
        let r = Array.isArray(e) ? e : [...(e != null ? [e] : []), ...t];
        return this._encode(r).join("");
    }
    
    encodeHex(e) {
        let t = e.toString(16);
        let r = p_split(t, 12, e => Number.parseInt(`1${e}`, 16));
        return this.encode(r);
    }
    
    _encode(e) {
        let t = this.alphabet;
        let r = e.reduce((e, t, r) => e + (t % (r + 100)), 0);
        let i = [t[r % t.length]];
        let s = [...i];
        let o = this.seps;
        let a = this.guards;
        e.forEach((r, a) => {
            let n = s.concat(this.salt, t);
            let c = d_encode(r, t = l_shuffle(t, n));
            i.push(...c);
            if (a + 1 < e.length) {
                let e = c[0].charCodeAt(0) + a;
                let t = r % e;
                i.push(o[t % o.length]);
            }
        });
        return i;
    }
}

// c_hash XOR function (95 key)
function c_hash(input) {
    const keyXor = 95;
    return Array.from(input)
        .map(c => c.charCodeAt(0))
        .map(code => {
            let hex = (code ^ keyXor).toString(16);
            return hex.length === 1 ? "0" + hex : hex;
        })
        .join("");
}

// HTTPS helper returning JSON/text
function fetchHTTPS(urlStr, options = {}) {
    return new Promise((resolve, reject) => {
        const parsedUrl = url.parse(urlStr);
        const reqOptions = {
            hostname: parsedUrl.hostname,
            path: parsedUrl.path,
            port: parsedUrl.port || 443,
            method: options.method || 'GET',
            headers: options.headers || {}
        };
        const req = https.request(reqOptions, (res) => {
            let body = '';
            res.on('data', chunk => body += chunk);
            res.on('end', () => {
                if (res.statusCode >= 200 && res.statusCode < 300) {
                    resolve(body);
                } else {
                    reject(new Error(`HTTP ${res.statusCode}: ${body}`));
                }
            });
        });
        req.on('error', reject);
        if (options.body) {
            req.write(options.body);
        }
        req.end();
    });
}

// TMDB Metadata fetch
async function fetchTMDBDetails(tmdbId, type) {
    const apiKey = "3d421899d5ce93db8ad4ae4591ccc130";
    const path = type === 'movie' ? `movie/${tmdbId}` : `tv/${tmdbId}`;
    const urlStr = `https://api.themoviedb.org/3/${path}?api_key=${apiKey}&append_to_response=external_ids`;
    try {
        const body = await fetchHTTPS(urlStr);
        const json = JSON.parse(body);
        const title = json.title || json.name || json.original_title || "";
        const dateStr = (type === 'movie' ? json.release_date : json.first_air_date) || "";
        const year = parseInt(dateStr.split("-")[0]) || 2000;
        const imdbId = json.imdb_id || (json.external_ids && json.external_ids.imdb_id) || "";
        const totalSeasons = json.number_of_seasons || 0;
        return { title, year, imdbId, totalSeasons };
    } catch (e) {
        console.error("TMDB error:", e);
        return null;
    }
}

// Create native Server
const server = http.createServer(async (req, res) => {
    const parsedUrl = url.parse(req.url, true);
    
    if (parsedUrl.pathname === '/api/resolve') {
        res.writeHead(200, { 
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        });
        
        const tmdbId = parsedUrl.query.tmdbId;
        const type = parsedUrl.query.type || 'movie';
        const season = parseInt(parsedUrl.query.season) || 1;
        const episode = parseInt(parsedUrl.query.episode) || 1;
        
        if (!tmdbId) {
            return res.end(JSON.stringify({ error: "Missing tmdbId parameter" }));
        }
        
        try {
            const steps = [];
            steps.push(`[1/6] Querying TMDB details for ID ${tmdbId}...`);
            const details = await fetchTMDBDetails(tmdbId, type);
            if (!details) {
                throw new Error("Failed to fetch media metadata from TMDb.");
            }
            steps.push(`  ↳ Found: "${details.title}" (${details.year}), IMDb: ${details.imdbId}`);
            
            steps.push(`[2/6] Querying seed from Wingsdatabase...`);
            const seedBody = await fetchHTTPS(`https://api.wingsdatabase.com/seed?mediaId=${tmdbId}`, {
                headers: {
                    'Referer': 'https://www.cineby.at/',
                    'Origin': 'https://www.cineby.at',
                    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
                }
            });
            const seedJson = JSON.parse(seedBody);
            const seed = seedJson.seed;
            if (!seed) {
                throw new Error("Failed to fetch keystream seed.");
            }
            steps.push(`  ↳ Seed retrieved: ${seed}`);
            
            steps.push(`[3/6] Generating authentication token (b35ebba4)...`);
            const inputToHash = `${tmdbId}d486ae1ce6fdbe63b60bd1704541fcf0`;
            const hashValue = c_hash(inputToHash);
            const hashids = new Hashids();
            const b35ebba4 = hashids.encodeHex(hashValue);
            steps.push(`  ↳ Token calculated: ${b35ebba4}`);
            
            steps.push(`[4/6] Querying encrypted sources-with-title...`);
            const encodedTitle = encodeURIComponent(details.title);
            const sourcesUrl = `https://api.wingsdatabase.com/mbx/sources-with-title?title=${encodedTitle}&mediaType=${type}&year=${details.year}&totalSeasons=${details.totalSeasons}&episodeId=${episode}&seasonId=${season}&tmdbId=${tmdbId}&imdbId=${details.imdbId}&enc=2&seed=${seed}&b35ebba4=${b35ebba4}`;
            
            const encryptedBase64 = await fetchHTTPS(sourcesUrl, {
                headers: {
                    'Referer': 'https://www.cineby.at/',
                    'Origin': 'https://www.cineby.at',
                    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
                }
            });
            steps.push(`  ↳ Encrypted payload downloaded (${encryptedBase64.length} bytes)`);
            
            steps.push(`[5/6] Initializing custom RC4 decryption engine...`);
            let decryptedStr;
            try {
                decryptedStr = decrypt(encryptedBase64.trim(), seed, parseInt(tmdbId));
            } catch (err) {
                // If it's empty array
                try {
                    const plain = JSON.parse(encryptedBase64);
                    if (plain.sources && plain.sources.length === 0) {
                        return res.end(JSON.stringify({ steps, sources: [], subtitles: [] }));
                    }
                } catch(e) {}
                throw err;
            }
            const decryptedJson = JSON.parse(decryptedStr);
            steps.push(`  ↳ Keystream decrypted. Extracted ${decryptedJson.sources.length} sources and ${decryptedJson.subtitles.length} subtitles.`);
            
            steps.push(`[6/6] Resolution complete!`);
            
            res.end(JSON.stringify({
                steps,
                sources: decryptedJson.sources,
                subtitles: decryptedJson.subtitles
            }));
            
        } catch (e) {
            res.end(JSON.stringify({ error: e.message }));
        }
    } else {
        // Serve HTML Client Frontend
        res.writeHead(200, { 'Content-Type': 'text/html' });
        res.end(`
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Cineby Stream Resolver Panel</title>
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;600;800&display=swap" rel="stylesheet">
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
            font-family: 'Outfit', sans-serif;
        }
        body {
            background: radial-gradient(circle at center, #1b263b 0%, #0d1b2a 100%);
            color: #ffffff;
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
            padding: 40px 20px;
            overflow-y: auto;
        }
        .container {
            width: 100%;
            max-width: 1100px;
            display: grid;
            grid-template-columns: 1fr 1.2fr;
            gap: 30px;
        }
        @media (max-width: 900px) {
            .container {
                grid-template-columns: 1fr;
            }
        }
        .card {
            background: rgba(255, 255, 255, 0.03);
            backdrop-filter: blur(25px) saturate(180%);
            -webkit-backdrop-filter: blur(25px) saturate(180%);
            border: 1px solid rgba(255, 255, 255, 0.08);
            border-radius: 24px;
            padding: 35px;
            box-shadow: 0 15px 35px rgba(0, 0, 0, 0.4);
            display: flex;
            flex-direction: column;
            gap: 24px;
            height: fit-content;
        }
        h1 {
            font-size: 28px;
            font-weight: 800;
            background: linear-gradient(135deg, #00d2ff 0%, #0066ff 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            letter-spacing: -0.5px;
            margin-bottom: 5px;
        }
        p.subtitle {
            font-size: 13px;
            color: rgba(255, 255, 255, 0.6);
            margin-top: -15px;
        }
        .form-group {
            display: flex;
            flex-direction: column;
            gap: 8px;
        }
        label {
            font-size: 11px;
            font-weight: 600;
            color: rgba(255, 255, 255, 0.5);
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        input, select {
            background: rgba(255, 255, 255, 0.05);
            border: 1px solid rgba(255, 255, 255, 0.1);
            border-radius: 12px;
            padding: 14px 16px;
            color: #ffffff;
            font-size: 15px;
            transition: all 0.3s ease;
            outline: none;
        }
        input:focus, select:focus {
            border-color: #00d2ff;
            background: rgba(255, 255, 255, 0.08);
            box-shadow: 0 0 10px rgba(0, 210, 255, 0.2);
        }
        .grid-2 {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 16px;
        }
        button {
            background: linear-gradient(135deg, #00d2ff 0%, #0066ff 100%);
            border: none;
            border-radius: 14px;
            padding: 16px;
            color: #ffffff;
            font-size: 16px;
            font-weight: 700;
            cursor: pointer;
            transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
            box-shadow: 0 8px 24px rgba(0, 102, 255, 0.3);
            display: flex;
            justify-content: center;
            align-items: center;
            gap: 8px;
        }
        button:hover {
            transform: translateY(-2px);
            box-shadow: 0 12px 30px rgba(0, 102, 255, 0.5);
            filter: brightness(1.1);
        }
        button:active {
            transform: translateY(1px);
        }
        .results-panel {
            display: flex;
            flex-direction: column;
            gap: 20px;
        }
        .console-log {
            background: rgba(0, 0, 0, 0.4);
            border: 1px solid rgba(255, 255, 255, 0.05);
            border-radius: 16px;
            padding: 18px;
            font-family: monospace;
            font-size: 12px;
            line-height: 1.6;
            color: #a9b7c6;
            height: 180px;
            overflow-y: auto;
            white-space: pre-wrap;
        }
        .console-log .success { color: #00e676; }
        .console-log .info { color: #00b0ff; }
        .console-log .error { color: #ff5252; }
        
        .video-container {
            border-radius: 16px;
            overflow: hidden;
            border: 1px solid rgba(255, 255, 255, 0.1);
            background: #000;
            aspect-ratio: 16/9;
            display: none;
        }
        video {
            width: 100%;
            height: 100%;
        }
        .sources-list {
            display: flex;
            flex-direction: column;
            gap: 12px;
            max-height: 300px;
            overflow-y: auto;
        }
        .source-item {
            background: rgba(255, 255, 255, 0.03);
            border: 1px solid rgba(255, 255, 255, 0.05);
            border-radius: 12px;
            padding: 14px 18px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            transition: all 0.2s ease;
        }
        .source-item:hover {
            background: rgba(255, 255, 255, 0.06);
            border-color: rgba(255, 255, 255, 0.1);
        }
        .source-info {
            display: flex;
            align-items: center;
            gap: 10px;
        }
        .source-name {
            font-weight: 600;
            font-size: 14px;
        }
        .source-quality {
            font-size: 11px;
            background: rgba(0, 210, 255, 0.1);
            color: #00d2ff;
            padding: 4px 8px;
            border-radius: 6px;
            font-weight: 800;
        }
        .play-btn {
            background: rgba(255, 255, 255, 0.1);
            color: #ffffff;
            box-shadow: none;
            padding: 8px 16px;
            border-radius: 8px;
            font-size: 13px;
            border: none;
            cursor: pointer;
            transition: all 0.2s;
        }
        .play-btn:hover {
            background: #ffffff;
            color: #000000;
            box-shadow: 0 4px 12px rgba(255, 255, 255, 0.2);
        }
        .subtitles-panel {
            display: flex;
            flex-wrap: wrap;
            gap: 8px;
            max-height: 100px;
            overflow-y: auto;
            padding: 5px;
        }
        .sub-badge {
            font-size: 11px;
            background: rgba(255, 255, 255, 0.06);
            border: 1px solid rgba(255, 255, 255, 0.08);
            color: rgba(255, 255, 255, 0.7);
            padding: 4px 10px;
            border-radius: 20px;
        }
        .spinner {
            width: 20px;
            height: 20px;
            border: 2px solid rgba(255,255,255,0.3);
            border-top-color: #fff;
            border-radius: 50%;
            animation: spin 0.8s linear infinite;
            display: none;
        }
        @keyframes spin {
            to { transform: rotate(360deg); }
        }
    </style>
</head>
<body>
    <div class="container">
        <!-- Input parameters Form -->
        <div class="card">
            <div>
                <h1>Cineby.at Resolver</h1>
                <p class="subtitle">Enter TMDB parameters to extract direct MP4 urls</p>
            </div>
            
            <div class="form-group">
                <label for="tmdbId">TMDB ID</label>
                <input type="text" id="tmdbId" placeholder="e.g. 550" value="550">
            </div>
            
            <div class="form-group">
                <label for="mediaType">Media Type</label>
                <select id="mediaType">
                    <option value="movie">Movie</option>
                    <option value="tv">TV Show</option>
                </select>
            </div>
            
            <div class="grid-2" id="tvParams" style="display: none;">
                <div class="form-group">
                    <label for="season">Season</label>
                    <input type="number" id="season" value="1" min="1">
                </div>
                <div class="form-group">
                    <label for="episode">Episode</label>
                    <input type="number" id="episode" value="1" min="1">
                </div>
            </div>
            
            <button onclick="resolveStream()">
                <span>Resolve Stream</span>
                <div class="spinner" id="spinner"></div>
            </button>
        </div>
        
        <!-- Decryption Output dashboard -->
        <div class="card results-panel">
            <label>Decryption log & pipeline</label>
            <div class="console-log" id="console">Ready to resolve. Enter parameters on the left.</div>
            
            <!-- Video Player panel -->
            <label id="playerLabel" style="display: none;">HTML5 Stream Player</label>
            <div class="video-container" id="videoContainer">
                <video id="player" controls autoplay></video>
            </div>
            
            <!-- Extracted Streams -->
            <label id="streamsLabel" style="display: none;">Decrypted MP4 Sources</label>
            <div class="sources-list" id="sourcesList"></div>
            
            <!-- Extracted Subtitles -->
            <label id="subsLabel" style="display: none;">Decrypted Subtitles</label>
            <div class="subtitles-panel" id="subtitlesList"></div>
        </div>
    </div>
    
    <script>
        const mediaTypeSelect = document.getElementById('mediaType');
        const tvParams = document.getElementById('tvParams');
        
        mediaTypeSelect.addEventListener('change', () => {
            tvParams.style.display = mediaTypeSelect.value === 'tv' ? 'grid' : 'none';
        });
        
        function log(message, type = 'info') {
            const consoleBox = document.getElementById('console');
            const className = type === 'success' ? 'success' : (type === 'error' ? 'error' : '');
            consoleBox.innerHTML += \`<div class="\${className}">\${message}</div>\`;
            consoleBox.scrollTop = consoleBox.scrollHeight;
        }
        
        function clearLog() {
            document.getElementById('console').innerHTML = '';
        }
        
        async function resolveStream() {
            const tmdbId = document.getElementById('tmdbId').value.trim();
            const type = document.getElementById('mediaType').value;
            const season = document.getElementById('season').value;
            const episode = document.getElementById('episode').value;
            
            if (!tmdbId) {
                alert('Please enter a TMDB ID');
                return;
            }
            
            const spinner = document.getElementById('spinner');
            spinner.style.display = 'block';
            clearLog();
            log('Starting stream resolution process...', 'info');
            
            // Hide player and sources lists
            document.getElementById('videoContainer').style.display = 'none';
            document.getElementById('playerLabel').style.display = 'none';
            document.getElementById('streamsLabel').style.display = 'none';
            document.getElementById('subsLabel').style.display = 'none';
            document.getElementById('sourcesList').innerHTML = '';
            document.getElementById('subtitlesList').innerHTML = '';
            document.getElementById('player').src = '';
            
            try {
                const res = await fetch(\`/api/resolve?tmdbId=\${tmdbId}&type=\${type}&season=\${season}&episode=\${episode}\`);
                const data = await res.json();
                
                if (data.error) {
                    log(\`Error: \${data.error}\`, 'error');
                    spinner.style.display = 'none';
                    return;
                }
                
                // Print back-end steps
                data.steps.forEach(step => {
                    if (step.includes('↳')) {
                        log(step, 'info');
                    } else if (step.includes('complete') || step.includes('Keystream decrypted')) {
                        log(step, 'success');
                    } else {
                        log(step, 'info');
                    }
                });
                
                if (data.sources.length === 0) {
                    log('No stream sources found for this title.', 'error');
                } else {
                    document.getElementById('streamsLabel').style.display = 'block';
                    const list = document.getElementById('sourcesList');
                    
                    data.sources.forEach(src => {
                        const div = document.createElement('div');
                        div.className = 'source-item';
                        div.innerHTML = \`
                            <div class="source-info">
                                <span class="source-name">\${src.name || 'Stream Source'}</span>
                                <span class="source-quality">\${src.quality || 'HD'}</span>
                            </div>
                            <button class="play-btn" onclick="playVideo('\${src.file}')">Play Source</button>
                        \`;
                        list.appendChild(div);
                    });
                    
                    // Auto-play first source if it's MP4
                    const firstFile = data.sources[0].file;
                    if (firstFile) {
                        playVideo(firstFile);
                    }
                }
                
                if (data.subtitles && data.subtitles.length > 0) {
                    document.getElementById('subsLabel').style.display = 'block';
                    const subsList = document.getElementById('subtitlesList');
                    data.subtitles.forEach(sub => {
                        const span = document.createElement('span');
                        span.className = 'sub-badge';
                        span.innerText = sub.label || sub.lang || 'Sub';
                        subsList.appendChild(span);
                    });
                }
                
            } catch (err) {
                log(\`Network error during resolution: \${err.message}\`, 'error');
            } finally {
                spinner.style.display = 'none';
            }
        }
        
        function playVideo(url) {
            const playerLabel = document.getElementById('playerLabel');
            const container = document.getElementById('videoContainer');
            const video = document.getElementById('player');
            
            playerLabel.style.display = 'block';
            container.style.display = 'block';
            video.src = url;
            video.play();
            log(\`Loaded stream URL into player: \${url.substring(0, 70)}...\`, 'success');
        }
    </script>
</body>
</html>
        `);
    }
});

const PORT = 3000;
server.listen(PORT, () => {
    console.log(`\x1b[36m==================================================`);
    console.log(`🚀 Cineby Stream Resolver Test Server is now running!`);
    console.log(`👉 Open: \x1b[1m\x1b[32mhttp://localhost:${PORT}\x1b[0m`);
    console.log(`==================================================\x1b[0m`);
});
