export function byteLength(value: string): number {
  let bytes = 0;
  for (let index = 0; index < value.length; index++) {
    const code = value.charCodeAt(index);
    if (code < 0x80) {
      bytes += 1;
    } else if (code < 0x800) {
      bytes += 2;
    } else if (code >= 0xD800 && code <= 0xDBFF && index + 1 < value.length) {
      const next = value.charCodeAt(index + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) {
        bytes += 4;
        index += 1;
      } else {
        bytes += 3;
      }
    } else {
      bytes += 3;
    }
  }
  return bytes;
}

export function parseJsonObject(value: string): Record<string, Object> {
  const parsed = JSON.parse(value) as Object;
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new Error('Expected a JSON object.');
  }
  return parsed as Record<string, Object>;
}

export function numberValue(value: Object | undefined, fallback: number = 0): number {
  if (value === undefined || value === null) {
    return fallback;
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export function stringValue(value: Object | undefined, fallback: string = ''): string {
  if (value === undefined || value === null) {
    return fallback;
  }
  return String(value);
}

export function booleanValue(value: Object | undefined, fallback: boolean = false): boolean {
  if (value === undefined || value === null) {
    return fallback;
  }
  return Boolean(value);
}

export function objectValue(value: Object | undefined): Record<string, Object> {
  if (value === undefined || value === null || typeof value !== 'object' || Array.isArray(value)) {
    return {};
  }
  return value as Record<string, Object>;
}

export function arrayValue(value: Object | undefined): Object[] {
  return Array.isArray(value) ? value as Object[] : [];
}
