import { describe, expect, it } from "vitest";
import { BridgeRpcError, classify, ErrorCode, parseFrame, request } from "../src/protocol/index.js";

describe("classify", () => {
  it("recognises requests, notifications and responses", () => {
    expect(classify(request(1, "scene_inspect", {})).kind).toBe("request");
    expect(classify({ jsonrpc: "2.0", method: "scene_changed" }).kind).toBe("notification");
    expect(classify({ jsonrpc: "2.0", id: 1, result: null }).kind).toBe("success");
    expect(classify({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "Parse error" } }).kind).toBe(
      "failure",
    );
  });

  it.each([
    ["non-object", 42],
    ["wrong version", { jsonrpc: "1.0", id: 1, result: 1 }],
    ["both result and error", { jsonrpc: "2.0", id: 1, result: 1, error: { code: 1, message: "x" } }],
    ["neither result nor error", { jsonrpc: "2.0", id: 1 }],
    ["malformed error", { jsonrpc: "2.0", id: 1, error: { code: "bad", message: "x" } }],
    ["null request id", { jsonrpc: "2.0", id: null, method: "x" }],
    ["scalar params", { jsonrpc: "2.0", id: 1, method: "x", params: 3 }],
  ])("rejects %s", (_label, raw) => {
    expect(classify(raw).kind).toBe("invalid");
  });
});

describe("parseFrame", () => {
  it("handles batches", () => {
    const frame = JSON.stringify([
      { jsonrpc: "2.0", id: 1, result: {} },
      { jsonrpc: "2.0", id: 2, error: { code: ErrorCode.NODE_NOT_FOUND, message: "nope" } },
    ]);
    expect(parseFrame(frame).map((m) => m.kind)).toEqual(["success", "failure"]);
  });

  it("reports invalid JSON and empty batches", () => {
    expect(parseFrame("{nope")[0]?.kind).toBe("invalid");
    expect(parseFrame("[]")[0]?.kind).toBe("invalid");
  });

  it("accepts Godot-style float ids", () => {
    // Godot's JSON.stringify may write integral floats as "1.0".
    const [msg] = parseFrame('{"jsonrpc":"2.0","id":1.0,"result":true}');
    expect(msg?.kind === "success" && msg.message.id).toBe(1);
  });
});

describe("BridgeRpcError", () => {
  it("round-trips error objects and names known codes", () => {
    const err = BridgeRpcError.fromObject({ code: ErrorCode.UNAUTHORIZED, message: "no", data: { a: 1 } });
    expect(err.codeName).toBe("UNAUTHORIZED");
    expect(err.toObject()).toEqual({ code: -32000, message: "no", data: { a: 1 } });
    expect(new BridgeRpcError(123, "x").codeName).toBeUndefined();
  });
});
