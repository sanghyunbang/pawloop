import http from "k6/http";
import { check, group, sleep } from "k6";
import { BASE_URL, envInt, jsonHeaders, parseJson } from "../../lib/config.js";

const VUS = envInt("VUS", 10);
const DURATION = __ENV.DURATION || "5m";
const SLEEP_SECONDS = Number(__ENV.SLEEP_SECONDS || "0.3");

export const options = {
  scenarios: {
    curation_non_llm_baseline: {
      executor: "constant-vus",
      vus: VUS,
      duration: DURATION,
    },
  },
  thresholds: {
    http_req_failed: ["rate<0.02"],
    "http_req_duration{endpoint:curation_rank}": ["p(95)<1000", "p(99)<3000"],
    "http_req_duration{endpoint:curation_categories}": ["p(95)<1000", "p(99)<3000"],
    "http_req_duration{endpoint:curation_recommend_skip_llm}": ["p(95)<1200", "p(99)<3500"],
  },
};

function rankPayload() {
  return {
    pad: {
      pleasure: 1,
      arousal: -1,
      dominance: 1,
    },
    energy: 1,
    socialNeed: 0.2,
    goals: ["nature_healing", "quiet_reflection"],
    purposeKeywords: ["walk", "view"],
    topK: 20,
    notes: "k6 non-llm baseline",
    moodKey: "calm",
    moodEmoji: ":)",
    cat3Filter: (__ENV.CAT3_FILTER || "A02010100,A02020700")
      .split(",")
      .map((item) => item.trim())
      .filter((item) => item.length > 0),
    userLat: Number(__ENV.USER_LAT || "37.5665"),
    userLng: Number(__ENV.USER_LNG || "126.9780"),
    maxDistanceKm: 120.0,
    distanceWeight: 0.2,
  };
}

export default function () {
  const headers = jsonHeaders();
  const payload = JSON.stringify(rankPayload());

  group("curation rank", () => {
    const res = http.post(`${BASE_URL}/api/curation/rank`, payload, {
      headers,
      tags: { endpoint: "curation_rank" },
    });

    check(res, {
      "rank status 200": (r) => r.status === 200,
      "rank body json": (r) => parseJson(r) !== null,
    });
  });

  group("curation categories", () => {
    const res = http.post(`${BASE_URL}/api/curation/categories`, payload, {
      headers,
      tags: { endpoint: "curation_categories" },
    });

    check(res, {
      "categories status 200": (r) => r.status === 200,
      "categories body json": (r) => parseJson(r) !== null,
    });
  });

  group("curation recommend without llm", () => {
    const res = http.post(`${BASE_URL}/api/curation/recommend`, payload, {
      headers,
      tags: { endpoint: "curation_recommend_skip_llm" },
    });

    check(res, {
      "recommend skip-llm status 200": (r) => r.status === 200,
      "recommend skip-llm body json": (r) => parseJson(r) !== null,
    });
  });

  sleep(SLEEP_SECONDS);
}
