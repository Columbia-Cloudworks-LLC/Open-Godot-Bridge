/**
 * The discovery file the plugin writes to `<project>/.godot/ogb_bridge/session.json`
 * while the bridge is running. It carries the bound port and the shared
 * secret required by `bridge.handshake`.
 */

import { readFile } from "node:fs/promises";
import { join } from "node:path";
import * as z from "zod";
import { SESSION_FILE_RELATIVE_PATH } from "./constants.js";

export const sessionFileSchema = z.object({
  protocol_version: z.int(),
  plugin_version: z.string(),
  host: z.string(),
  port: z.int().min(1).max(65535),
  token: z.string().min(1),
  pid: z.int(),
  godot_version: z.string(),
  started_at: z.string(),
});
export type SessionFile = z.infer<typeof sessionFileSchema>;

export function sessionFilePath(projectRoot: string): string {
  return join(projectRoot, SESSION_FILE_RELATIVE_PATH);
}

export class SessionFileError extends Error {
  override readonly name = "SessionFileError";
}

/**
 * Reads the session file of the project at `projectRoot`.
 * Returns null when no bridge is running (file absent); throws
 * SessionFileError when the file exists but is malformed.
 */
export async function readSessionFile(projectRoot: string): Promise<SessionFile | null> {
  const path = sessionFilePath(projectRoot);
  let text: string;
  try {
    text = await readFile(path, "utf8");
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") return null;
    throw err;
  }
  let json: unknown;
  try {
    json = JSON.parse(text);
  } catch (err) {
    throw new SessionFileError(`${path} is not valid JSON: ${(err as Error).message}`);
  }
  const parsed = sessionFileSchema.safeParse(json);
  if (!parsed.success) {
    throw new SessionFileError(`${path} is malformed: ${z.prettifyError(parsed.error)}`);
  }
  return parsed.data;
}
