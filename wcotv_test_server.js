const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const url = require('url');
const { execFile } = require("node:child_process");
const { promisify } = require("node:util");
const execFileAsync = promisify(execFile);

const PORT = 3001;
const SOURCE = {
  id: "wcotv",
  name: "WCO.tv",
  baseUrl: "https://www.wco.tv"
};
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36";

async function requestText(url, extraHeaders = {}) {
  const args = [
    "-s", "-L", "--max-time", "30",
    "-A", UA,
    "-H", "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "-H", "Accept-Language: en-US,en;q=0.9",
    "-H", `Referer: ${SOURCE.baseUrl}/`
  ];
  for (const [k, v] of Object.entries(extraHeaders)) {
    args.push("-H", `${k}: ${v}`);
  }
  args.push(url);
  const { stdout } = await execFileAsync("curl", args, { maxBuffer: 10 * 1024 * 1024, timeout: 30000 });
  return stdout;
}

function decodeHtml(s) {
  return (s || "")
    .replace(/&amp;/g, "&")
    .replace(/&quot;/g, '"')
    .replace(/&#039;|&#39;|&apos;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&nbsp;/g, " ")
    .replace(/&#(\d+);/g, (_, d) => String.fromCharCode(+d));
}

function cleanText(s) {
  return decodeHtml((s || "").replace(/<script[\s\S]*?<\/script>/gi, " ").replace(/<[^>]+>/g, " "))
    .replace(/\s+/g, " ")
    .trim();
}

function absoluteUrl(url, base = SOURCE.baseUrl) {
  if (!url) return null;
  const v = decodeHtml(String(url).trim());
  if (/^https?:\/\//i.test(v)) return v;
  if (v.startsWith("//")) return "https:" + v;
  if (v.startsWith("/")) return base + v;
  return base + "/" + v;
}

function attr(tag, name) {
  const m = (tag || "").match(new RegExp(`\\s${name}=["']([^"']+)["']`, "i"));
  return m ? decodeHtml(m[1]) : null;
}

function episodeSlugFromUrl(url) {
  const v = String(url || "").replace(/\/$/, "");
  const m = v.match(/\/([^/]+)$/);
  return m ? m[1] : "";
}

function parseShowCards(html) {
  const items = [];
  const seen = new Set();
  const liRe = /<li[^>]*>([\s\S]*?)<\/li>/gi;
  let m;
  while ((m = liRe.exec(html || "")) !== null) {
    const block = m[1];
    const linkM = block.match(/<a\s+href=["']([^"']*\/anime\/([^/"'\s]+))["'][^>]*/i);
    if (!linkM) continue;
    const id = linkM[2].replace(/\/$/, "");
    if (!id || seen.has(id)) continue;
    seen.add(id);
    const imgTag = block.match(/<img[^>]+>/i)?.[0] || "";
    const cover = attr(imgTag, "data-src") || attr(imgTag, "data-lazy-src") || attr(imgTag, "src");
    const titleEl = block.match(/<span[^>]*>([^<]{3,})<\/span>/i)
      || block.match(/<div[^>]*class=["'][^"']*title[^"']*["'][^>]*>([^<]+)<\/div>/i);
    const title = titleEl
      ? cleanText(titleEl[1])
      : (attr(imgTag, "alt") || decodeHtml(id.replace(/-/g, " ")));
    items.push({ id, title, cover: cover ? absoluteUrl(cover) : null });
  }
  if (items.length === 0) {
    const linkRe = /<a\s+href=["']([^"']*\/anime\/([^/"'\s]+))["'][^>]*(?:\s+title=["']([^"']+)["'])?[^>]*>([^<]*)/gi;
    while ((m = linkRe.exec(html || "")) !== null) {
      const id = m[2].replace(/\/$/, "");
      if (!id || seen.has(id)) continue;
      seen.add(id);
      const title = decodeHtml((m[3] || m[4] || id.replace(/-/g, " ")).trim());
      items.push({ id, title, cover: null });
    }
  }
  return items;
}

async function searchAnime(query) {
  const q = (query || "").trim();
  if (!q) return [];
  const args = [
    "-s", "-L", "--max-time", "30",
    "-A", UA,
    "-H", "Accept: */*",
    "-H", "Accept-Language: en-US,en;q=0.9",
    "-H", `Referer: ${SOURCE.baseUrl}/`,
    "-H", "X-Requested-With: XMLHttpRequest",
    "--data", `catara=${encodeURIComponent(q)}&konuara=series`,
    `${SOURCE.baseUrl}/search`
  ];
  const { stdout } = await execFileAsync("curl", args, { maxBuffer: 5 * 1024 * 1024, timeout: 30000 });
  return parseShowCards(stdout || "");
}

async function getEpisodes(itemId) {
  const url = `${SOURCE.baseUrl}/anime/${itemId}/`;
  const html = await requestText(url);
  const titleM = html.match(/<h2[^>]*class=["'][^"']*cat-genre[^"']*["'][^>]*>([\s\S]*?)<\/h2>/i) || html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i);
  const seriesTitle = titleM ? cleanText(titleM[1]) : itemId;
  const out = [];
  const seen = new Set();
  
  const epLinkRe = /<a\s+href=["']([^"']+)["'][^>]*(?:\s+title=["']([^"']+)["'])?[^>]*>([^<]*)/gi;
  let m;
  while ((m = epLinkRe.exec(html || "")) !== null) {
    const href = m[1];
    const label = cleanText(m[2] || m[3] || "");
    if (!/episode/i.test(`${href} ${label}`)) continue;
    if (/\/anime\//i.test(href)) continue;
    const absHref = /^https?:\/\//i.test(href) ? href : absoluteUrl(href);
    const slug = episodeSlugFromUrl(absHref) || href.replace(/^\/|\/$/g, "");
    if (!slug || seen.has(slug)) continue;
    seen.add(slug);
    const epNumM = slug.match(/episode[- ]?(\d+(?:\.\d+)?)/i) || label.match(/(\d+(?:\.\d+)?)/);
    const number = epNumM ? parseFloat(epNumM[1]) : out.length + 1;
    const isDub = /dub(?:bed)?/i.test(`${href} ${label}`);
    out.push({ id: slug, number, title: label || `${seriesTitle} Episode ${number}`, type: isDub ? "Dubbed" : "Subbed" });
  }
  
  const idWords = itemId.split("-").filter(w => w.length >= 4);
  let relevant = out;
  if (idWords.length > 0) {
    relevant = out.filter(e => idWords.some(w => e.id.toLowerCase().includes(w)));
  }
  const finalEpisodes = relevant.length > 0 ? relevant : out;
  return finalEpisodes.sort((a, b) => a.number - b.number || (a.type === "Dubbed" ? 1 : -1));
}

async function getStreams(episodeId) {
  const slug = String(episodeId || "").replace(/^\/|\/$/g, "");
  const episodeUrl = `${SOURCE.baseUrl}/${slug}/`;
  const pageHtml = await requestText(episodeUrl).catch(() => null);
  if (!pageHtml) return [];
  
  const oreMatch = pageHtml.match(/var ([A-Za-z][A-Za-z]*)\s*=\s*\[([\s\S]*?)\];\s*\1\.forEach/);
  if (!oreMatch) return [];
  const constMatch = pageHtml.match(/\)\s*-\s*(\d{6,})\s*\)/);
  const constant = constMatch ? parseInt(constMatch[1]) : 51973287;
  const tokens = [...oreMatch[2].matchAll(/"([A-Za-z0-9+/=]+)"/g)].map(m => m[1]);
  let PMx = "";
  for (const tok of tokens) {
    try {
      const decoded = Buffer.from(tok, "base64").toString("latin1");
      const digits = decoded.replace(/\D/g, "");
      if (digits) {
        const code = parseInt(digits) - constant;
        if (code > 0 && code < 0x110000) PMx += String.fromCodePoint(code);
      }
    } catch {}
  }
  if (!PMx) return [];
  
  const iframeM = PMx.match(/src=["']([^"']+embed\.wcostream\.com[^"']+)["']/i) || PMx.match(/<iframe[^>]+src=["']([^"']+)["']/i);
  if (!iframeM) return [];
  const iframeSrc = decodeHtml(iframeM[1]);
  const fileParamM = iframeSrc.match(/[?&]file=([^&]+)/);
  if (!fileParamM) return [];
  const filePath = decodeURIComponent(fileParamM[1]).replace(/\.flv$/i, ".mp4");
  const encodedPath = filePath.split("/").map(s => encodeURIComponent(s)).join("/");
  const getvidlinkUrl = `https://embed.wcostream.com/inc/embed/getvidlink.php?v=neptun/${encodedPath}&embed=neptun&fullhd=1`;
  
  let vidJson;
  try {
    const { stdout } = await execFileAsync("curl", [
      "-s", "-L", "--max-time", "20", "-A", UA,
      "-H", `Referer: ${iframeSrc}`,
      "-H", "X-Requested-With: XMLHttpRequest",
      getvidlinkUrl
    ], { maxBuffer: 1 * 1024 * 1024, timeout: 25000 });
    vidJson = JSON.parse(stdout);
  } catch(e) {
    return [];
  }
  
  const server = vidJson.server || vidJson.cdn;
  if (!server) return [];
  
  const result = [];
  for (const [key, token, label] of [
    ["fhd", vidJson.fhd, "1080p"],
    ["hd", vidJson.hd, "720p"],
    ["enc", vidJson.enc, "480p"],
  ]) {
    if (!token) continue;
    result.push({
      label,
      url: `${server}/getvid?evid=${encodeURIComponent(token)}`,
      referer: iframeSrc
    });
  }
  return result;
}

// HTTP Server
const server = http.createServer(async (req, res) => {
  const parsedUrl = url.parse(req.url, true);
  const pathname = parsedUrl.pathname;
  
  // Set CORS headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  
  if (req.method === 'OPTIONS') {
    res.writeHead(200);
    res.end();
    return;
  }
  
  if (pathname === '/' || pathname === '/index.html') {
    fs.readFile(path.join(__dirname, 'index.html'), (err, content) => {
      if (err) {
        res.writeHead(500, { 'Content-Type': 'text/plain' });
        res.end('Error loading index.html');
      } else {
        res.writeHead(200, { 'Content-Type': 'text/html' });
        res.end(content);
      }
    });
    return;
  }
  
  // Proxy endpoint to stream video to client, following redirects on the server side
  if (pathname === '/api/proxy') {
    const streamUrl = parsedUrl.query.url;
    const referer = parsedUrl.query.referer;
    if (!streamUrl) {
      res.writeHead(400);
      res.end('Missing url');
      return;
    }
    
    function performRequest(targetUrl) {
      const parsedStreamUrl = url.parse(targetUrl);
      const options = {
        hostname: parsedStreamUrl.hostname,
        port: parsedStreamUrl.port,
        path: parsedStreamUrl.path,
        method: 'GET',
        headers: {
          'User-Agent': UA,
          'Referer': referer || SOURCE.baseUrl
        }
      };
      
      const proxyReq = (parsedStreamUrl.protocol === 'https:' ? https : http).request(options, (proxyRes) => {
        if (proxyRes.statusCode === 302 || proxyRes.statusCode === 301) {
          const redirectUrl = proxyRes.headers.location;
          performRequest(redirectUrl);
        } else {
          // Copy status and headers, then pipe the data
          res.writeHead(proxyRes.statusCode, proxyRes.headers);
          proxyRes.pipe(res);
        }
      });
      
      proxyReq.on('error', (err) => {
        res.writeHead(500);
        res.end('Proxy error: ' + err.message);
      });
      
      proxyReq.end();
    }
    
    performRequest(streamUrl);
    return;
  }
  
  // API endpoints
  if (pathname === '/api/search') {
    const q = parsedUrl.query.q || '';
    try {
      const results = await searchAnime(q);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(results));
    } catch(e) {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: e.message }));
    }
    return;
  }
  
  if (pathname === '/api/episodes') {
    const id = parsedUrl.query.id || '';
    try {
      const episodes = await getEpisodes(id);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(episodes));
    } catch(e) {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: e.message }));
    }
    return;
  }
  
  if (pathname === '/api/streams') {
    const id = parsedUrl.query.id || '';
    try {
      const streams = await getStreams(id);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(streams));
    } catch(e) {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: e.message }));
    }
    return;
  }
  
  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('Not Found');
});

server.listen(PORT, () => {
  console.log(`WCO.tv Anime Test Server listening on http://localhost:${PORT}`);
});
