/**
 * JSON-RPC 2.0 envelope types and a strict classifier for inbound frames.
 * https://www.jsonrpc.org/specification
 */

export type JsonRpcId = string | number | null;

export interface JsonRpcRequest<P = unknown> {
  jsonrpc: "2.0";
  id: string | number;
  method: string;
  params?: P;
}

export interface JsonRpcNotification<P = unknown> {
  jsonrpc: "2.0";
  method: string;
  params?: P;
}

export interface JsonRpcErrorObject {
  code: number;
  message: string;
  data?: unknown;
}

export interface JsonRpcSuccess<R = unknown> {
  jsonrpc: "2.0";
  id: JsonRpcId;
  result: R;
}

export interface JsonRpcFailure {
  jsonrpc: "2.0";
  id: JsonRpcId;
  error: JsonRpcErrorObject;
}

export type JsonRpcResponse<R = unknown> = JsonRpcSuccess<R> | JsonRpcFailure;

export type JsonRpcMessage = JsonRpcRequest | JsonRpcNotification | JsonRpcResponse;

export type ClassifiedMessage =
  | { kind: "request"; message: JsonRpcRequest }
  | { kind: "notification"; message: JsonRpcNotification }
  | { kind: "success"; message: JsonRpcSuccess }
  | { kind: "failure"; message: JsonRpcFailure }
  | { kind: "invalid"; reason: string; raw: unknown };

export function request<P>(id: string | number, method: string, params?: P): JsonRpcRequest<P> {
  return params === undefined ? { jsonrpc: "2.0", id, method } : { jsonrpc: "2.0", id, method, params };
}

export function notification<P>(method: string, params?: P): JsonRpcNotification<P> {
  return params === undefined ? { jsonrpc: "2.0", method } : { jsonrpc: "2.0", method, params };
}

export function isFailure<R>(response: JsonRpcResponse<R>): response is JsonRpcFailure {
  return "error" in response;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isId(value: unknown): value is JsonRpcId {
  return value === null || typeof value === "string" || (typeof value === "number" && Number.isFinite(value));
}

function isErrorObject(value: unknown): value is JsonRpcErrorObject {
  return isObject(value) && Number.isInteger(value.code) && typeof value.message === "string";
}

/** Classifies a single decoded JSON value as a JSON-RPC message. */
export function classify(raw: unknown): ClassifiedMessage {
  const invalid = (reason: string): ClassifiedMessage => ({ kind: "invalid", reason, raw });

  if (!isObject(raw)) return invalid("message is not an object");
  if (raw.jsonrpc !== "2.0") return invalid('"jsonrpc" must be "2.0"');

  if ("method" in raw) {
    if (typeof raw.method !== "string") return invalid('"method" must be a string');
    if ("params" in raw && !isObject(raw.params) && !Array.isArray(raw.params)) {
      return invalid('"params" must be an object or array');
    }
    if (!("id" in raw)) return { kind: "notification", message: raw as unknown as JsonRpcNotification };
    if (typeof raw.id !== "string" && typeof raw.id !== "number") {
      return invalid('request "id" must be a string or number');
    }
    return { kind: "request", message: raw as unknown as JsonRpcRequest };
  }

  if (!("id" in raw) || !isId(raw.id)) return invalid('response "id" must be a string, number or null');
  const hasResult = "result" in raw;
  const hasError = "error" in raw;
  if (hasResult === hasError) return invalid('response must have exactly one of "result" or "error"');
  if (hasError) {
    if (!isErrorObject(raw.error)) return invalid('"error" must have an integer "code" and a string "message"');
    return { kind: "failure", message: raw as unknown as JsonRpcFailure };
  }
  return { kind: "success", message: raw as unknown as JsonRpcSuccess };
}

/**
 * Parses one WebSocket text frame. A frame is a single message or a batch
 * (array); an undecodable frame yields a single "invalid" entry.
 */
export function parseFrame(text: string): ClassifiedMessage[] {
  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch (err) {
    return [{ kind: "invalid", reason: `invalid JSON: ${(err as Error).message}`, raw: text }];
  }
  if (Array.isArray(raw)) {
    return raw.length === 0 ? [{ kind: "invalid", reason: "empty batch", raw }] : raw.map(classify);
  }
  return [classify(raw)];
}
