const MIXIN_KEY_ENC_TAB: number[] = [
  46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49,
  33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13, 37, 48, 7, 16, 24, 55, 40, 61,
  26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36,
  20, 34, 44, 52
];

export interface WbiParams {
  searchType: string;
  keyword: string;
  page: number;
  pageSize: number;
}

export function mixinKeyFromKeys(imgKey: string, subKey: string): string {
  const original = `${imgKey}${subKey}`;
  let mixed = '';
  for (const index of MIXIN_KEY_ENC_TAB) {
    mixed += original.charAt(index);
  }
  return mixed.slice(0, 32);
}

export function canonicalWbiQuery(params: WbiParams, timestamp: number): string {
  const values: Record<string, string> = {
    'keyword': params.keyword,
    'page': `${params.page}`,
    'page_size': `${params.pageSize}`,
    'search_type': params.searchType,
    'wts': `${timestamp}`
  };
  const keys = Object.keys(values).sort();
  const parts: string[] = [];
  for (const key of keys) {
    const value = values[key].replace(/[!'()*]/gu, '');
    parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(value)}`);
  }
  return parts.join('&');
}

export function wbiQuery(params: WbiParams, timestamp: number, imgKey: string, subKey: string): string {
  const query = canonicalWbiQuery(params, timestamp);
  const signature = md5Hex(`${query}${mixinKeyFromKeys(imgKey, subKey)}`);
  return `${query}&w_rid=${signature}`;
}

export function md5Hex(input: string): string {
  const bytes = utf8Bytes(input);
  const paddedLength = Math.ceil((bytes.length + 9) / 64) * 64;
  const padded = new Uint8Array(paddedLength);
  padded.set(bytes);
  padded[bytes.length] = 0x80;
  const view = new DataView(padded.buffer);
  view.setUint32(paddedLength - 8, (bytes.length * 8) >>> 0, true);
  view.setUint32(paddedLength - 4, Math.floor((bytes.length * 8) / 0x100000000), true);

  let a0 = 0x67452301;
  let b0 = 0xEFCDAB89;
  let c0 = 0x98BADCFE;
  let d0 = 0x10325476;
  for (let offset = 0; offset < paddedLength; offset += 64) {
    const words: number[] = [];
    for (let index = 0; index < 16; index++) {
      const position = offset + index * 4;
      words.push((padded[position] | (padded[position + 1] << 8) |
        (padded[position + 2] << 16) | (padded[position + 3] << 24)) >>> 0);
    }
    let a = a0;
    let b = b0;
    let c = c0;
    let d = d0;
    for (let index = 0; index < 64; index++) {
      let roundValue = 0;
      let wordIndex = 0;
      if (index < 16) {
        roundValue = (b & c) | (~b & d);
        wordIndex = index;
      } else if (index < 32) {
        roundValue = (d & b) | (~d & c);
        wordIndex = (5 * index + 1) % 16;
      } else if (index < 48) {
        roundValue = b ^ c ^ d;
        wordIndex = (3 * index + 5) % 16;
      } else {
        roundValue = c ^ (b | ~d);
        wordIndex = (7 * index) % 16;
      }
      const nextB = (b + rotateLeft((a + roundValue + MD5_CONSTANTS[index] + words[wordIndex]) >>> 0,
        MD5_SHIFTS[index])) >>> 0;
      const previousD = d;
      d = c;
      c = b;
      b = nextB;
      a = previousD;
    }
    a0 = (a0 + a) >>> 0;
    b0 = (b0 + b) >>> 0;
    c0 = (c0 + c) >>> 0;
    d0 = (d0 + d) >>> 0;
  }
  return [a0, b0, c0, d0].map((word: number): string => littleEndianHex(word)).join('');
}

function utf8Bytes(input: string): Uint8Array {
  const bytes: number[] = [];
  for (let index = 0; index < input.length; index++) {
    let codePoint = input.charCodeAt(index);
    if (codePoint >= 0xD800 && codePoint <= 0xDBFF) {
      if (index + 1 < input.length) {
        const low = input.charCodeAt(index + 1);
        if (low >= 0xDC00 && low <= 0xDFFF) {
          codePoint = 0x10000 + ((codePoint - 0xD800) << 10) + (low - 0xDC00);
          index++;
        } else {
          codePoint = 0xFFFD;
        }
      } else {
        codePoint = 0xFFFD;
      }
    } else if (codePoint >= 0xDC00 && codePoint <= 0xDFFF) {
      codePoint = 0xFFFD;
    }

    if (codePoint <= 0x7F) {
      bytes.push(codePoint);
    } else if (codePoint <= 0x7FF) {
      bytes.push(0xC0 | (codePoint >> 6));
      bytes.push(0x80 | (codePoint & 0x3F));
    } else if (codePoint <= 0xFFFF) {
      bytes.push(0xE0 | (codePoint >> 12));
      bytes.push(0x80 | ((codePoint >> 6) & 0x3F));
      bytes.push(0x80 | (codePoint & 0x3F));
    } else {
      bytes.push(0xF0 | (codePoint >> 18));
      bytes.push(0x80 | ((codePoint >> 12) & 0x3F));
      bytes.push(0x80 | ((codePoint >> 6) & 0x3F));
      bytes.push(0x80 | (codePoint & 0x3F));
    }
  }
  const encoded = new Uint8Array(bytes.length);
  for (let index = 0; index < bytes.length; index++) {
    encoded[index] = bytes[index];
  }
  return encoded;
}

const MD5_SHIFTS: number[] = [
  7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
  5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
  4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
  6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
];

const MD5_CONSTANTS: number[] = [
  0xD76AA478, 0xE8C7B756, 0x242070DB, 0xC1BDCEEE, 0xF57C0FAF, 0x4787C62A, 0xA8304613, 0xFD469501,
  0x698098D8, 0x8B44F7AF, 0xFFFF5BB1, 0x895CD7BE, 0x6B901122, 0xFD987193, 0xA679438E, 0x49B40821,
  0xF61E2562, 0xC040B340, 0x265E5A51, 0xE9B6C7AA, 0xD62F105D, 0x02441453, 0xD8A1E681, 0xE7D3FBC8,
  0x21E1CDE6, 0xC33707D6, 0xF4D50D87, 0x455A14ED, 0xA9E3E905, 0xFCEFA3F8, 0x676F02D9, 0x8D2A4C8A,
  0xFFFA3942, 0x8771F681, 0x6D9D6122, 0xFDE5380C, 0xA4BEEA44, 0x4BDECFA9, 0xF6BB4B60, 0xBEBFBC70,
  0x289B7EC6, 0xEAA127FA, 0xD4EF3085, 0x04881D05, 0xD9D4D039, 0xE6DB99E5, 0x1FA27CF8, 0xC4AC5665,
  0xF4292244, 0x432AFF97, 0xAB9423A7, 0xFC93A039, 0x655B59C3, 0x8F0CCC92, 0xFFEFF47D, 0x85845DD1,
  0x6FA87E4F, 0xFE2CE6E0, 0xA3014314, 0x4E0811A1, 0xF7537E82, 0xBD3AF235, 0x2AD7D2BB, 0xEB86D391
];

function rotateLeft(value: number, bits: number): number {
  return ((value << bits) | (value >>> (32 - bits))) >>> 0;
}

function littleEndianHex(value: number): string {
  let output = '';
  for (let offset = 0; offset < 32; offset += 8) {
    output += ((value >>> offset) & 0xFF).toString(16).padStart(2, '0');
  }
  return output;
}

export function parseWbiKeys(imgUrl: string, subUrl: string): string[] {
  const imgKey = fileNameWithoutExtension(imgUrl);
  const subKey = fileNameWithoutExtension(subUrl);
  if (imgKey.length === 0 || subKey.length === 0) {
    return [];
  }
  return [imgKey, subKey];
}

function fileNameWithoutExtension(rawUrl: string): string {
  const clean = rawUrl.split('?')[0];
  const slash = clean.lastIndexOf('/');
  const name = slash >= 0 ? clean.slice(slash + 1) : clean;
  const dot = name.indexOf('.');
  return dot >= 0 ? name.slice(0, dot) : name;
}
