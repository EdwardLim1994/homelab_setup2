// Minimal HTTP wrapper around mermaid-cli's `mmdc`, mirroring
// helm/omp/adapter/server.py's plain-stdlib style. POST raw Mermaid source
// to /render, get an SVG back. No framework, no persistence — this pod only
// exists while something is actively rendering (see
// helm/omp/scripts/render-mermaid.sh, which scales it 0 -> 1 -> 0).
//
// ponytail: SVG, not PNG -- a fixed-pixel raster made diagram text
// illegible once embedded in the PDF at print scale. mmdc renders true
// vector SVG just as easily (same -o extension-detection), and the PDF
// pipeline already has rsvg-convert on PATH (confirmed in pandoc/extra) to
// embed it losslessly via xelatex -- no resolution ceiling either way.
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
    const outFile = path.join(os.tmpdir(), `${id}.svg`);
    fs.writeFileSync(inFile, mermaidSrc);

    const args = ['-i', inFile, '-o', outFile, '-b', 'white'];
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
        const svg = fs.readFileSync(outFile);
        res.writeHead(200, { 'Content-Type': 'image/svg+xml' });
        res.end(svg);
      } finally {
        fs.unlink(inFile, () => {});
        fs.unlink(outFile, () => {});
      }
    });
  });
}).listen(PORT, () => console.log(`mermaid-render listening on :${PORT}`));
