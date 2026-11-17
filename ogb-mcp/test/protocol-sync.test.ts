/**
 * Guards against drift between the GDScript and TypeScript halves of the
 * protocol by parsing the constants out of protocol.gd.
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import * as P from "../src/protocol/index.js";

const GD_PATH = fileURLToPath(new URL("../../addons/ogb_bridge/core/protocol.gd", import.meta.url));

function parseGdConstants(source: string): Map<string, string | number> {
  const out = new Map<string, string | number>();
  const re = /^const\s+([A-Z0-9_]+)\s*:?=\s*(.+?)\s*(?:#.*)?$/gm;
  for (const [, name, expr] of source.matchAll(re)) {
    if (name === undefined || expr === undefined) continue;
    if (/^".*"$/.test(expr)) {
      out.set(name, expr.slice(1, -1));
    } else if (/^[-\d\s.*+]+$/.test(expr)) {
      // Plain numeric literals and products like "4 * 1024 * 1024".
      out.set(name, expr.split("*").reduce((acc, part) => acc * Number(part.trim()), 1));
    } else {
      throw new Error(`Unrecognised constant expression in protocol.gd: ${name} = ${expr}`);
    }
  }
  return out;
}

const gd = parseGdConstants(readFileSync(GD_PATH, "utf8"));

describe("protocol.gd <-> TypeScript", () => {
  it("parses a sensible number of constants", () => {
    expect(gd.size).toBeGreaterThan(20);
  });

  it.each([
    ["PROTOCOL_VERSION", P.PROTOCOL_VERSION],
    ["DEFAULT_PORT", P.DEFAULT_PORT],
    ["PORT_RANGE", P.PORT_RANGE],
    ["BIND_ADDRESS", P.BIND_ADDRESS],
    ["SESSION_FILE_PATH", `res://${P.SESSION_FILE_RELATIVE_PATH}`],
    ["AUTH_TIMEOUT_SEC", P.AUTH_TIMEOUT_SEC],
    ["MAX_INBOUND_BYTES", P.MAX_INBOUND_BYTES],
    ["MAX_OUTBOUND_BYTES", P.MAX_OUTBOUND_BYTES],
    ["CLOSE_AUTH_TIMEOUT", P.CLOSE_AUTH_TIMEOUT],
  ] as const)("%s matches", (name, value) => {
    expect(gd.get(name)).toBe(value);
  });

  it("defines the same method names", () => {
    const gdMethods = [...gd].filter(([k, v]) => k.startsWith("METHOD_") && typeof v === "string").map(([k, v]) => [k.slice("METHOD_".length), v]);
    expect(Object.fromEntries(gdMethods)).toEqual(P.Method);
  });

  it("defines the same error codes", () => {
    const gdCodes = [...gd].filter(([, v]) => typeof v === "number" && v <= -32000 && v >= -32768);
    expect(Object.fromEntries(gdCodes)).toEqual(P.ErrorCode);
  });

  it("uses the same plugin version as plugin.cfg", () => {
    const cfg = readFileSync(new URL("../../addons/ogb_bridge/plugin.cfg", import.meta.url), "utf8");
    expect(cfg).toContain(`version="${gd.get("PLUGIN_VERSION")}"`);
  });
});
