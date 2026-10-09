// Minimal HTTP wrapper around mermaid-cli's `mmdc`, mirroring
// helm/omp/adapter/server.py's plain-stdlib style. POST raw Mermaid source
// to /render, get a PNG back. No framework, no persistence — this pod only
// exists while something is actively rendering (see
// helm/omp/scripts/render-mermaid.sh, which scales it 0 -> 1 -> 0).
//
// ponytail: PNG, not SVG -- mermaid (v12, confirmed) renders flowchart/
// class/state labels as HTML <foreignObject> content regardless of the
// htmlLabels:false config (a known mermaid limitation on the new unified
// renderer, not something this config can turn off). rsvg-convert -- what
// the PDF pipeline uses to embed an SVG via xelatex -- can't render
// foreignObject HTML at all, so every diagram came through with shapes but
// zero visible words. mmdc renders PNG through the same Chromium/puppeteer
// pass that drew the page in the first place, so foreignObject labels show
// up correctly; -s (scale) below trades the vector-SVG's "no resolution
// ceiling" for a high-enough fixed DPI to stay legible at print scale.
const http = require('http');
const { execFile } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

const PORT = process.env.PORT || 4098;

http.createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/health') {
    res.writeHead(200); res.end('ok'); return;
  }
  if (req.method !== 'POST' || req.url !== '/render') {
    res.writeHead(404); res.end('not found'); return;
  }

  const chunks = [];
  req.on('data', (c) => chunks.push(c));
  req.on('end', () => {
    const mermaidSrc = Buffer.concat(chunks).toString('utf8');
    const id = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
    const inFile = path.join(os.tmpdir(), `${id}.mmd`);
    const outFile = path.join(os.tmpdir(), `${id}.png`);
    fs.writeFileSync(inFile, mermaidSrc);

    const args = ['-i', inFile, '-o', outFile, '-b', 'white', '-s', '3'];
    // minlag/mermaid-cli ships a sandbox-safe puppeteer config at this
    // fixed path when one is needed in a container — use it if present.
    if (fs.existsSync('/puppeteer-config.json')) {
      args.push('-p', '/puppeteer-config.json');
    }

    execFile('mmdc', args, { timeout: 30000 }, (err, stdout, stderr) => {
      try {
        if (err) {
          res.writeHead(500, { 'Content-Type': 'text/plain' });
          res.end(`mmdc failed: ${err.message}\n${stderr}`);
          return;
        }
        const png = fs.readFileSync(outFile);
        res.writeHead(200, { 'Content-Type': 'image/png' });
        res.end(png);
      } finally {
        fs.unlink(inFile, () => {});
        fs.unlink(outFile, () => {});
      }
    });
  });
}).listen(PORT, () => console.log(`mermaid-render listening on :${PORT}`));
