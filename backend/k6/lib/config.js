export const BASE_URL = (__ENV.BASE_URL || "http://localhost:8080").replace(/\/+$/, "");

export function envInt(name, fallback) {
  const parsed = Number.parseInt(__ENV[name], 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export function envFloat(name, fallback) {
  const parsed = Number.parseFloat(__ENV[name]);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export function jsonHeaders(token = "") {
  const headers = {
    Accept: "application/json",
    "Content-Type": "application/json",
  };

  if (token) {
    headers.Authorization = `Bearer ${token}`;
  }

  return headers;
}

export function shortId() {
  return `${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
}

export function parseJson(response, fallback = null) {
  try {
    return response.json();
  } catch (_) {
    return fallback;
  }
}

export function makeText(chars, prefix = "k6-load-test") {
  const target = Math.max(chars, prefix.length);
  return `${prefix} ${"x".repeat(target)}`.slice(0, target);
}

