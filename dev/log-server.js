// Simple diagnostics collector for Fremio's Advanced Console.
// Receives POSTed logs from the app, stores them, prints them, and serves a
// live web viewer. No external dependencies — plain Node http/fs.
//
//   node dev/log-server.js            (defaults to port 8787, all interfaces)
//   PORT=9000 node dev/log-server.js
//
// Point the app's Settings -> Diagnostics -> "Report Endpoint" at:
//   http://<this-machine-LAN-IP>:8787/log

const http = require("http");
const fs = require("fs");
const path = require("path");
const os = require("os");

const PORT = parseInt(process.env.PORT || "8787", 10);
const STORE = path.join(__dirname, "received-logs.jsonl");

function lanIPs() {
  const out = [];
  const ifaces = os.networkInterfaces();
  for (const name of Object.keys(ifaces)) {
    for (const net of ifaces[name] || []) {
      if (net.family === "IPv4" && !net.internal) out.push(net.address);
    }
  }
  return out;
}

function cors(res) {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
}

function readReports() {
  try {
    return fs
      .readFileSync(STORE, "utf8")
      .split("\n")
      .filter(Boolean)
      .map((l) => {
        try {
          return JSON.parse(l);
        } catch {
          return null;
        }
      })
      .filter(Boolean);
  } catch {
    return [];
  }
}

const server = http.createServer((req, res) => {
  cors(res);

  if (req.method === "OPTIONS") {
    res.writeHead(204);
    res.end();
    return;
  }

  // Receive a report (accept POST on any path so the endpoint is forgiving).
  if (req.method === "POST") {
    let body = "";
    req.on("data", (c) => {
      body += c;
      if (body.length > 5_000_000) req.destroy(); // 5 MB guard
    });
    req.on("end", () => {
      let parsed;
      try {
        parsed = JSON.parse(body);
      } catch {
        parsed = { unparsed: body };
      }
      const record = { receivedAt: new Date().toISOString(), report: parsed };
      fs.appendFileSync(STORE, JSON.stringify(record) + "\n");

      const entries = Array.isArray(parsed?.entries) ? parsed.entries : [];
      const errors = entries.filter((e) => e.level === "error").length;
      console.log(
        `\n[${record.receivedAt}] report received — ${entries.length} entries (${errors} errors)` +
          (parsed?.app ? `  app=${parsed.app}` : "") +
          (parsed?.system ? `  system=${parsed.system}` : "")
      );
      for (const e of entries.slice(0, 40)) {
        console.log(`  • [${(e.level || "?").toUpperCase()}] ${e.category}: ${e.message}`);
        if (e.detail) {
          console.log("      " + String(e.detail).replace(/\n/g, "\n      "));
        }
      }

      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ ok: true, received: entries.length }));
    });
    return;
  }

  // Raw JSON of everything received.
  if (req.method === "GET" && req.url.startsWith("/raw")) {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify(readReports(), null, 2));
    return;
  }

  // Live HTML viewer.
  if (req.method === "GET") {
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    res.end(VIEWER_HTML);
    return;
  }

  res.writeHead(404);
  res.end();
});

const VIEWER_HTML = `<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Fremio Log Collector</title>
<style>
  body{font:14px -apple-system,Segoe UI,Roboto,sans-serif;background:#0d0d12;color:#eee;margin:0;padding:16px}
  h1{font-size:16px;margin:0 0 4px}
  .sub{color:#888;font-size:12px;margin-bottom:16px}
  .rep{border:1px solid #222;border-radius:8px;margin-bottom:12px;overflow:hidden}
  .rh{background:#15151d;padding:8px 12px;font-size:12px;color:#9ad}
  .e{padding:8px 12px;border-top:1px solid #1a1a22}
  .cat{font-size:10px;font-weight:700;letter-spacing:.05em}
  .error .cat{color:#f66}.warning .cat{color:#fc4}.info .cat{color:#4cf}
  .msg{margin:2px 0}
  .detail{font:11px ui-monospace,Menlo,monospace;color:#9a9aa5;white-space:pre-wrap;background:#111;border-radius:6px;padding:6px;margin-top:4px}
  .empty{color:#666;padding:40px;text-align:center}
</style></head><body>
<h1>Fremio Log Collector</h1>
<div class="sub">Live — auto-refreshing every 3s. Newest report first.</div>
<div id="root"><div class="empty">Waiting for the app to send logs…</div></div>
<script>
async function tick(){
  try{
    const reports = await (await fetch('/raw')).json();
    const root = document.getElementById('root');
    if(!reports.length){root.innerHTML='<div class="empty">Waiting for the app to send logs…</div>';return;}
    root.innerHTML = reports.slice().reverse().map(r=>{
      const p = r.report||{};
      const entries = Array.isArray(p.entries)?p.entries:[];
      const head = '<div class="rh">'+r.receivedAt+' — '+entries.length+' entries'+(p.app?' · '+p.app:'')+(p.system?' · '+p.system:'')+'</div>';
      const rows = entries.map(e=>'<div class="e '+(e.level||'')+'"><div class="cat">'+(e.level||'?').toUpperCase()+' · '+(e.category||'')+'</div><div class="msg">'+esc(e.message||'')+'</div>'+(e.detail?'<div class="detail">'+esc(e.detail)+'</div>':'')+'</div>').join('');
      return '<div class="rep">'+head+rows+'</div>';
    }).join('');
  }catch(e){}
}
function esc(s){return String(s).replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));}
tick();setInterval(tick,3000);
</script></body></html>`;

server.listen(PORT, "0.0.0.0", () => {
  console.log("Fremio log collector listening on port " + PORT);
  console.log("Local viewer:   http://localhost:" + PORT + "/");
  const ips = lanIPs();
  if (ips.length) {
    console.log("From the phone, set Report Endpoint to one of:");
    for (const ip of ips) console.log("   http://" + ip + ":" + PORT + "/log");
  }
});
