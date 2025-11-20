#!/usr/bin/env node
// usage: node find_double_quoted_long_alpha.js [root-path]
// Example: node find_double_quoted_long_alpha.js .
// If no root-path is provided, the script defaults to the project's `k_back` directory.

const fs = require('fs').promises;
const path = require('path');

const argRoot = process.argv[2];
const defaultRoot = path.resolve(__dirname, '..', '..', 'k_back');
const root = argRoot || defaultRoot;
const EXTS = ['.py'];

async function walk(dir) {
  const entries = await fs.readdir(dir, { withFileTypes: true });
  const files = [];
  for (const e of entries) {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) {
      // skip typical venv/build directories
      if (['.git', 'venv', 'node_modules', '__pycache__', '.tox'].includes(e.name)) continue;
      files.push(...await walk(full));
    } else if (e.isFile()) {
      if (EXTS.includes(path.extname(e.name))) files.push(full);
    }
  }
  return files;
}

function removeTripleQuotedBlocks(txt) {
  // remove both """...""" and '''...'''
  return txt.replace(/("{3}|'{3})[\s\S]*?\1/g, '');
}

function* iterDoubleQuotedStrings(txt) {
  // yield inner content of double-quoted strings while respecting escapes
  const re = /"((?:\\.|[^"\\])*)"/gs;
  let m;
  while ((m = re.exec(txt)) !== null) yield m[1];
}

function countLetters(s) {
  const m = s.match(/[A-Za-z]/g);
  return m ? m.length : 0;
}

function countJapanese(s) {
  try {
    // use Unicode property escapes (Node.js >= 10+)
    const m = s.match(/\p{Script=Hiragana}|\p{Script=Katakana}|\p{Script=Han}/gu);
    return m ? m.length : 0;
  } catch (e) {
    // fallback broad unicode ranges
    const m = s.match(/[\u3040-\u30ff\u4e00-\u9fff]/g);
    return m ? m.length : 0;
  }
}

(async function main() {
  const files = await walk(root);
  const hits = [];
  for (const f of files) {
    let txt;
    try {
      txt = await fs.readFile(f, 'utf8');
    } catch (e) {
      continue;
    }
    const cleaned = removeTripleQuotedBlocks(txt);
    let matched = false;
    for (const s of iterDoubleQuotedStrings(cleaned)) {
      if (s.includes('@')) continue; // email
      if (/https?:\/\//i.test(s)) continue; // url
      const low = s.toLowerCase();
      if (low.includes('patch') && low.includes('json')) continue; // contains both patch and json
      const letters = countLetters(s);
      const japanese = countJapanese(s);
      if (letters >= 10 && letters > japanese) {
        matched = true;
        break;
      }
    }
    if (matched) hits.push(f);
  }

  // print results
  if (hits.length === 0) {
    console.log('No matching files found.');
    process.exit(0);
  }
  for (const h of hits) console.log(h);
})();
