/** Simple output helpers — no external deps */

export function log(msg: string): void {
  if (!(globalThis as any).__consuelo_quiet) console.log(msg);
}

export function error(msg: string): void {
  console.error(`error: ${msg}`);
}

export function json(data: unknown): void {
  console.log(JSON.stringify(data, null, 2));
}

export function isJson(): boolean {
  return !!(globalThis as any).__consuelo_json;
}
