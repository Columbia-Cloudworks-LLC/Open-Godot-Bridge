#!/usr/bin/env node
// Manual smoke test for a running Godot editor with the ogb_bridge plugin.
//
//   node ogb-mcp/scripts/smoke.mjs [path/to/godot/project]
//
// Reads the session file, connects, handshakes, calls project_status and
// checks that bad requests produce the expected JSON-RPC errors.

import { readFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import WebSocket from "ws";

const projectRoot = resolve(process.argv[2] ?? ".");
const session = JSON.parse(await readFile(join(projectRoot, ".godot/ogb_bridge/session.json"), "utf8"));
const url = `ws://${session.host}:${session.port}`;
console.log(`Connecting to ${url} (Godot ${session.godot_version}, pid ${session.pid})`);

const ws = new WebSocket(url);
await new Promise((ok, fail) => ws.once("open", ok).once("error", fail));

let nextId = 1;
const pending = new Map();
ws.on("message", (data) => {
  const msg = JSON.parse(data.toString());
  for (const m of Array.isArray(msg) ? msg : [msg]) pending.get(m.id)?.(m);
});
const call = (method, params) =>
  new Promise((done) => {
    const id = nextId++;
    pending.set(id, done);
    ws.send(JSON.stringify({ jsonrpc: "2.0", id, method, params }));
  });
const sendRaw = (text) =>
  new Promise((done) => {
    ws.once("message", (data) => done(JSON.parse(data.toString())));
    ws.send(text);
  });

let failures = 0;
const check = (label, condition, detail) => {
  console.log(`${condition ? "PASS" : "FAIL"}  ${label}`);
  if (!condition) {
    failures++;
    console.log("      ", JSON.stringify(detail));
  }
};

const early = await call("project_status", {});
check("calls before handshake are rejected", early.error?.code === -32000, early);

const badToken = await call("bridge.handshake", { protocol_version: 1, token: "wrong", client: { name: "smoke", version: "0" } });
check("wrong token is rejected", badToken.error?.code === -32000, badToken);

const hello = await call("bridge.handshake", {
  protocol_version: 1,
  token: session.token,
  client: { name: "ogb-smoke", version: "0.1.0" },
});
check("handshake succeeds", hello.result?.protocol_version === 1, hello);
console.log("      methods:", hello.result?.methods?.join(", "));

const status = await call("project_status", {});
check("project_status returns project info", typeof status.result?.project?.path === "string", status);
console.log("      ", JSON.stringify(status.result));

const unknown = await call("does_not_exist", {});
check("unknown method -> METHOD_NOT_FOUND", unknown.error?.code === -32601, unknown);

const badParams = await call("project_status", [1, 2]);
check("positional params -> INVALID_PARAMS", badParams.error?.code === -32602, badParams);

const parseErr = await sendRaw("{not json");
check("garbage -> PARSE_ERROR", parseErr.error?.code === -32700, parseErr);

const batch = await sendRaw(
  JSON.stringify([
    { jsonrpc: "2.0", id: "a", method: "project_status" },
    { jsonrpc: "2.0", method: "project_status" },
    { jsonrpc: "2.0", id: "b", method: "nope" },
  ]),
);
check(
  "batch returns replies for requests only",
  Array.isArray(batch) && batch.length === 2 && batch[0].id === "a" && batch[1].error?.code === -32601,
  batch,
);

ws.close();

// A second connection that never authenticates must be dropped (code 4001).
const idle = new WebSocket(url);
const closeCode = await new Promise((done) => {
  const timer = setTimeout(() => done("still open after 8s"), 8000);
  idle.once("close", (code) => {
    clearTimeout(timer);
    done(code);
  });
});
check("unauthenticated connection closed after timeout", closeCode === 4001, closeCode);

console.log(failures === 0 ? "\nAll checks passed." : `\n${failures} check(s) failed.`);
process.exit(failures === 0 ? 0 : 1);
