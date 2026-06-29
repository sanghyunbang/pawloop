import http from "k6/http";
import { check } from "k6";
import { BASE_URL, jsonHeaders, shortId } from "./config.js";

const DEFAULT_PASSWORD = "Loadtest1234!";

export function getAuthToken() {
  if (__ENV.ACCESS_TOKEN) {
    return __ENV.ACCESS_TOKEN;
  }

  const email = __ENV.TEST_EMAIL || `k6-${shortId()}@example.test`;
  const password = __ENV.TEST_PASSWORD || DEFAULT_PASSWORD;

  const signupPayload = {
    email,
    password,
    nickname: __ENV.TEST_NICKNAME || `k6-${shortId()}`,
    name: __ENV.TEST_NAME || "k6 load tester",
    gender: "other",
    ageGroup: "over14",
    agreeTos: true,
    agreePrivacy: true,
    agreeMarketing: false,
    tosVersion: "v1.0",
    privacyVersion: "v1.0",
    marketingVersion: "v1.0",
  };

  const signupRes = http.post(
    `${BASE_URL}/auth/signup`,
    JSON.stringify(signupPayload),
    { headers: jsonHeaders(), tags: { endpoint: "auth_signup" } },
  );

  check(signupRes, {
    "signup accepted or existing test user": (r) => r.status >= 200 && r.status < 500,
  });

  const loginRes = http.post(
    `${BASE_URL}/auth/login`,
    JSON.stringify({ email, password }),
    { headers: jsonHeaders(), tags: { endpoint: "auth_login" } },
  );

  const ok = check(loginRes, {
    "login status 200": (r) => r.status === 200,
    "login returned token": (r) => Boolean(r.body && r.body.trim().length > 20),
  });

  if (!ok) {
    throw new Error(`Login failed. status=${loginRes.status} body=${loginRes.body}`);
  }

  return loginRes.body.replace(/^"|"$/g, "").trim();
}

