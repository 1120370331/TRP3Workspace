import luaparse from 'luaparse';
import { isDeepStrictEqual } from 'node:util';

const parse = source => luaparse.parse(source,{luaVersion:'5.1',comments:false});
function lex(source) {
  luaparse.parse(source,{luaVersion:'5.1',wait:true,comments:false});
  const tokens=[];
  for (let t=luaparse.lex();t.type!==1;t=luaparse.lex()) tokens.push({type:t.type,raw:source.slice(...t.range),offset:t.range[0],line:t.line});
  return tokens;
}
const identity = tokens => tokens.map(({type,raw})=>({type,raw}));

// Preserve every token, literal and identifier. A full AST comparison catches
// newline-sensitive Lua ambiguity as well as accidental token concatenation.
// Unlike a bytecode build, the output remains portable to WoW's Lua 5.1 host.
export function compileLua(source, {minify=false} = {}) {
  const ast=parse(source);
  if (!minify) return {code:source,map:null};
  const tokens=lex(source), separators=new Map(), pieces=[], map=[];
  let previous, offset=0, line=1;
  for (const token of tokens) {
    if (previous) {
      const key=previous.raw+'\0'+token.raw;
      if (!separators.has(key)) {
        let safe=false;
        try { safe=isDeepStrictEqual(identity(lex(previous.raw+token.raw)),identity([previous,token])); } catch {}
        // luaparse accepts e.g. "32then" as two tokens; native Lua 5.1 rejects
        // it as a malformed number. Preserve identifier/number word boundaries.
        if (/[A-Za-z0-9_]$/.test(previous.raw) && /^[A-Za-z0-9_]/.test(token.raw)) safe=false;
        if (previous.raw==='[' && (token.raw==='=' || token.raw==='[')) safe=false;
        separators.set(key,safe?'':' ');
      }
      // Keep code-line boundaries (collapse blank/comment-only lines). WoW's
      // stack traces have line numbers, so a single-line payload is undesirable.
      const separator=source.slice(previous.offset+previous.raw.length,token.offset).includes('\n')?'\n':separators.get(key);
      pieces.push(separator);offset+=separator.length;if(separator==='\n')line++;
    }
    map.push([offset,token.offset,token.line,line]);pieces.push(token.raw);offset+=token.raw.length;
    line+=token.raw.split('\n').length-1;previous=token;
  }
  const code=pieces.join('');
  if (!isDeepStrictEqual(identity(lex(code)),identity(tokens)) || !isDeepStrictEqual(parse(code),ast)) throw new Error('Lua minification changed tokens or syntax tree');
  return {code,map};
}
