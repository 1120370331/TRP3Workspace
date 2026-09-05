#!/usr/bin/env node

import { readFile, writeFile } from "node:fs/promises";
import { inflateRawSync } from "node:zlib";

const PRINT_ALPHABET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789()";

function fail(message) {
  throw new Error(`TRP3 export decode failed: ${message}`);
}

function decodeForPrint(value) {
  const encoded = value.trim();
  if (!encoded.startsWith("!")) {
    fail("expected the ! printable-export prefix");
  }

  const payload = encoded.slice(1);
  if (payload.length < 2) {
    fail("printable payload is too short");
  }

  const lookup = new Map([...PRINT_ALPHABET].map((character, index) => [character, index]));
  const bytes = [];
  let index = 0;

  while (index + 3 < payload.length) {
    const symbols = payload.slice(index, index + 4).split("").map((character) => lookup.get(character));
    if (symbols.some((symbol) => symbol === undefined)) {
      fail(`invalid printable character at offset ${index}`);
    }
    const cache = symbols[0] + symbols[1] * 64 + symbols[2] * 4096 + symbols[3] * 262144;
    bytes.push(cache & 0xff, (cache >>> 8) & 0xff, (cache >>> 16) & 0xff);
    index += 4;
  }

  let cache = 0;
  let bitLength = 0;
  while (index < payload.length) {
    const symbol = lookup.get(payload[index]);
    if (symbol === undefined) {
      fail(`invalid printable character at offset ${index}`);
    }
    cache += symbol * 2 ** bitLength;
    bitLength += 6;
    index += 1;
  }
  while (bitLength >= 8) {
    bytes.push(cache & 0xff);
    cache = Math.floor(cache / 256);
    bitLength -= 8;
  }

  return Buffer.from(bytes);
}

function unescapeAceString(value) {
  return value.replace(/~./g, (escape) => {
    const marker = escape[1];
    if (marker < "z") {
      return String.fromCharCode(marker.charCodeAt(0) - 64);
    }
    if (marker === "z") return String.fromCharCode(30);
    if (marker === "{") return String.fromCharCode(127);
    if (marker === "|") return "~";
    if (marker === "}") return "^";
    fail(`invalid AceSerializer escape ${JSON.stringify(escape)}`);
  });
}

function tokeniseAceSerializer(value) {
  const compact = value.replace(/[\x00-\x20]/g, "");
  const tokens = [];
  const pattern = /\^(.)([^\^]*)/g;
  let match;
  while ((match = pattern.exec(compact)) !== null) {
    tokens.push({ control: `^${match[1]}`, data: match[2] });
  }
  if (tokens[0]?.control !== "^1") {
    fail("payload is not AceSerializer protocol revision 1");
  }
  return tokens;
}

function decodeAceSerializer(value) {
  const tokens = tokeniseAceSerializer(value);
  let index = 1;

  function nextToken() {
    const token = tokens[index];
    index += 1;
    if (!token) {
      fail("AceSerializer payload ended before its terminator");
    }
    return token;
  }

  function readValue(token = nextToken()) {
    switch (token.control) {
      case "^S":
        return unescapeAceString(token.data);
      case "^N": {
        if (token.data === "inf" || token.data === "1.#INF") return Infinity;
        if (token.data === "-inf" || token.data === "-1.#INF") return -Infinity;
        const number = Number(token.data);
        if (!Number.isFinite(number)) fail(`invalid serialized number ${JSON.stringify(token.data)}`);
        return number;
      }
      case "^F": {
        const exponent = nextToken();
        if (exponent.control !== "^f") {
          fail(`expected ^f after floating-point mantissa, received ${exponent.control}`);
        }
        const mantissa = Number(token.data);
        const power = Number(exponent.data);
        if (!Number.isFinite(mantissa) || !Number.isFinite(power)) {
          fail("invalid floating-point components");
        }
        return mantissa * 2 ** power;
      }
      case "^B":
        return true;
      case "^b":
        return false;
      case "^Z":
        return null;
      case "^T": {
        const table = {};
        while (true) {
          const keyToken = nextToken();
          if (keyToken.control === "^t") break;
          const key = readValue(keyToken);
          if (key === null) fail("nil cannot be used as an AceSerializer table key");
          const entry = readValue();
          if (entry === null) continue;
          table[String(key)] = entry;
        }
        return table;
      }
      default:
        fail(`unsupported AceSerializer control code ${token.control}`);
    }
  }

  const result = [];
  while (index < tokens.length) {
    const token = nextToken();
    if (token.control === "^^") break;
    result.push(readValue(token));
  }
  return result;
}

function countEntries(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? Object.keys(value).length : 0;
}

function buildSummary(exportTuple) {
  const object = exportTuple?.["3"] && typeof exportTuple["3"] === "object" ? exportTuple["3"] : null;
  return {
    extendedVersion: exportTuple?.["1"] ?? null,
    objectId: exportTuple?.["2"] ?? null,
    objectType: object?.TY ?? null,
    objectName: object?.BA?.NA ?? null,
    objectVersion: object?.MD?.V ?? null,
    author: object?.MD?.CB ?? null,
    displayVersion: exportTuple?.["4"] ?? null,
    topLevelFields: object ? Object.keys(object).sort() : [],
    workflowCount: countEntries(object?.SC),
    childCounts: {
      IN: countEntries(object?.IN),
      QE: countEntries(object?.QE),
      ST: countEntries(object?.ST),
    },
  };
}

const [inputPath, outputPath] = process.argv.slice(2);
if (!inputPath || !outputPath) {
  console.error("Usage: node tools/decode-trp3-export.mjs <input.txt> <output.json>");
  process.exitCode = 1;
} else {
  const printableExport = await readFile(inputPath, "utf8");
  const compressed = decodeForPrint(printableExport);
  const serialized = inflateRawSync(compressed).toString("utf8").replaceAll("||", "|");
  const values = decodeAceSerializer(serialized);
  const exportTuple = values.length === 1 && values[0] && typeof values[0] === "object" ? values[0] : values;
  const report = {
    format: "TRP3 Extended short export",
    decoder: {
      printableCodec: "LibDeflate EncodeForPrint",
      compression: "C_EncodingUtil raw DEFLATE",
      serialization: "AceSerializer-3.0 revision 1",
    },
    sizes: {
      printableCharacters: printableExport.trim().length,
      compressedBytes: compressed.length,
      serializedBytes: Buffer.byteLength(serialized),
    },
    summary: buildSummary(exportTuple),
    exportTuple,
  };
  await writeFile(outputPath, `${JSON.stringify(report, null, 2)}\n`, "utf8");
  console.log(JSON.stringify(report.summary, null, 2));
}
