import type { JsonRpcErrorObject } from "./jsonrpc.js";

/**
 * JSON-RPC error codes. Keys match the constant names in
 * addons/ogb_bridge/core/protocol.gd.
 */
export const ErrorCode = {
  // JSON-RPC 2.0 reserved codes.
  PARSE_ERROR: -32700,
  INVALID_REQUEST: -32600,
  METHOD_NOT_FOUND: -32601,
  INVALID_PARAMS: -32602,
  INTERNAL_ERROR: -32603,

  // Bridge-level codes.
  UNAUTHORIZED: -32000,
  PROTOCOL_MISMATCH: -32001,

  // Editor/domain codes.
  NO_SCENE_OPEN: -32010,
  NODE_NOT_FOUND: -32011,
  INVALID_OPERATION: -32012,
  UNSAVED_CHANGES: -32013,
} as const;

export type ErrorCodeName = keyof typeof ErrorCode;
export type ErrorCodeValue = (typeof ErrorCode)[ErrorCodeName];

const NAME_BY_CODE = new Map<number, ErrorCodeName>(
  (Object.entries(ErrorCode) as [ErrorCodeName, number][]).map(([name, code]) => [code, name]),
);

/** Name of a known error code, or undefined for codes outside the protocol. */
export function errorCodeName(code: number): ErrorCodeName | undefined {
  return NAME_BY_CODE.get(code);
}

/** A JSON-RPC error returned by the Godot plugin. */
export class BridgeRpcError extends Error {
  override readonly name = "BridgeRpcError";

  constructor(
    readonly code: number,
    message: string,
    readonly data?: unknown,
  ) {
    super(message);
  }

  static fromObject(error: JsonRpcErrorObject): BridgeRpcError {
    return new BridgeRpcError(error.code, error.message, error.data);
  }

  get codeName(): ErrorCodeName | undefined {
    return errorCodeName(this.code);
  }

  toObject(): JsonRpcErrorObject {
    return this.data === undefined
      ? { code: this.code, message: this.message }
      : { code: this.code, message: this.message, data: this.data };
  }
}
