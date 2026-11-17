import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { readSessionFile, SessionFileError, sessionFilePath } from "../src/protocol/index.js";

let root: string;

beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), "ogb-session-"));
});
afterEach(async () => {
  await rm(root, { recursive: true, force: true });
});

async function writeSession(content: string) {
  const path = sessionFilePath(root);
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, content);
}

const valid = {
  protocol_version: 1,
  plugin_version: "0.1.0",
  host: "127.0.0.1",
  port: 6510,
  token: "abc123",
  pid: 4242,
  godot_version: "4.3-stable (official)",
  started_at: "2026-11-16T12:00:00Z",
};

describe("readSessionFile", () => {
  it("returns null when no bridge is running", async () => {
    expect(await readSessionFile(root)).toBeNull();
  });

  it("reads a valid file", async () => {
    await writeSession(JSON.stringify(valid));
    expect(await readSessionFile(root)).toEqual(valid);
  });

  it("throws on malformed content", async () => {
    await writeSession("{not json");
    await expect(readSessionFile(root)).rejects.toBeInstanceOf(SessionFileError);
    await writeSession(JSON.stringify({ ...valid, port: "6510" }));
    await expect(readSessionFile(root)).rejects.toThrow(/port/);
  });
});
