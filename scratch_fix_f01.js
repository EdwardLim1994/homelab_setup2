const fs = require('fs');
const p = 'helm/ansible/flows/F-01-plan-release.json';
let s = fs.readFileSync(p, 'utf8');
const before = "2. Table of Contents — omit the content, `publish-pdf.sh`'s pandoc call renders this automatically from headings via --toc.";
const after = "2. Table of Contents — body is exactly one fenced raw-LaTeX block and nothing else: ```{=latex}\\n\\\\tableofcontents\\n``` (no --toc flag is passed to pandoc -- that auto-inserts the TOC at the very top of the document with no title to anchor after, which is what pushed the Cover Page off page 1 last time; this raw block is how the real table of contents renders in the right place, right after the Cover Page).";
if (!s.includes(before)) { throw new Error('anchor not found'); }
s = s.split(before).join(after);
fs.writeFileSync(p, s);
JSON.parse(fs.readFileSync(p, 'utf8'));
console.log('JSON OK');
