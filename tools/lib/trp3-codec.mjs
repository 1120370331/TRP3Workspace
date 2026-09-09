import { deflateRawSync, inflateRawSync } from 'node:zlib';

const alphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789()';
export function encodeForPrint(buffer) {
  let bits = 0, value = 0, out = '';
  for (const byte of buffer) {
    value |= byte << bits;
    bits += 8;
    while (bits >= 6) { out += alphabet[value & 63]; value >>>= 6; bits -= 6; }
  }
  if (bits) out += alphabet[value & 63];
  return out;
}
export function decodeForPrint(text) {
  let bits = 0, value = 0;
  const bytes = [];
  for (const c of text) {
    const n = alphabet.indexOf(c);
    if (n < 0) throw new Error('Invalid LibDeflate print character');
    value |= n << bits; bits += 6;
    while (bits >= 8) { bytes.push(value & 255); value >>>= 8; bits -= 8; }
  }
  if (bits >= 6 || value !== 0) throw new Error('Noncanonical printable tail');
  return Buffer.from(bytes);
}
function escapeAce(text) {
  return text.replace(/[\x00-\x20\x5e\x7e\x7f]/g, c => {
    const n = c.charCodeAt(0);
    if (n === 30) return '~z';
    if (n === 127) return '~{';
    if (c === '~') return '~|';
    if (c === '^') return '~}';
    return '~' + String.fromCharCode(n + 64);
  });
}
export function serializeAce(value) {
  const seen = new Set();
  function encode(v) {
    if (v === null || v === undefined) return '^Z';
    if (typeof v === 'string') return '^S' + escapeAce(v);
    if (typeof v === 'number') {
      if (!Number.isFinite(v)) throw new Error('Non-finite number');
      return '^N' + String(v);
    }
    if (typeof v === 'boolean') return v ? '^B' : '^b';
    if (typeof v !== 'object' || seen.has(v)) throw new Error('Invalid/cyclic Ace table');
    seen.add(v);
    const pairs = Array.isArray(v)
      ? v.map((entry, index) => [index + 1, entry])
      : Object.keys(v).sort((a, b) => Buffer.compare(Buffer.from(a), Buffer.from(b))).map(k => [k, v[k]]);
    const out = '^T' + pairs.map(([k, entry]) => encode(k) + encode(entry)).join('') + '^t';
    seen.delete(v);
    return out;
  }
  return '^1' + encode(value) + '^^';
}
export function deserializeAce(text, typed = false) {
  const compact = text.replace(/[\x00-\x20]/g, '');
  const tokens = [...compact.matchAll(/\^(.)([^\^]*)/g)].map(m => [m[1], m[2]]);
  if (tokens[0]?.[0] !== '1') throw new Error('Invalid Ace revision');
  let i = 1;
  function read(depth = 0) {
    if (depth > 64) throw new Error('Ace depth limit');
    const token = tokens[i++];
    if (!token) throw new Error('Truncated Ace value');
    const [kind, data] = token;
    if (kind === 'S') return data.replace(/~./g, s => {
      if (s[1] < 'z') return String.fromCharCode(s.charCodeAt(1) - 64);
      if (s[1] === 'z') return '\x1e';
      if (s[1] === '{') return '\x7f';
      if (s[1] === '|') return '~';
      if (s[1] === '}') return '^';
      throw new Error('Invalid Ace escape');
    });
    if (kind === 'N') { const n = Number(data); if (!Number.isFinite(n)) throw new Error('Invalid number'); return n; }
    if (kind === 'F') {
      const exponent = tokens[i++];
      if (exponent?.[0] !== 'f') throw new Error('Missing exponent');
      const n = Number(data) * 2 ** Number(exponent[1]);
      if (!Number.isFinite(n)) throw new Error('Invalid float'); return n;
    }
    if (kind === 'B') return true;
    if (kind === 'b') return false;
    if (kind === 'Z') return null;
    if (kind === 'T') {
      const result = typed ? new Map() : Object.create(null);
      while (tokens[i]?.[0] !== 't') {
        const k = read(depth + 1), v = read(depth + 1);
        if (k === null || typeof k === 'object') throw new Error('Invalid table key');
        if (v !== null) { if (typed) result.set(k, v); else result[String(k)] = v; }
      }
      i++; return result;
    }
    throw new Error(`Unexpected Ace control ${kind}`);
  }
  const result = read();
  if (tokens[i]?.[0] !== '^' || i !== tokens.length - 1) throw new Error('Missing Ace terminator or trailing values');
  return result;
}
export function encodeExport(tuple) {
  return '!' + encodeForPrint(deflateRawSync(Buffer.from(serializeAce(tuple).replaceAll('|', '||')), { level: 9 }));
}
export function decodeExport(text, typed = false) {
  text = text.trim();
  if (!text.startsWith('!')) throw new Error('Expected ! short export');
  const raw = inflateRawSync(decodeForPrint(text.slice(1)), { maxOutputLength: 16 * 1024 * 1024 }).toString('utf8');
  return deserializeAce(raw.replaceAll('||', '|'), typed);
}
