import http from "k6/http";
import { check, group, sleep } from "k6";
import { getAuthToken } from "../../lib/auth.js";
import { BASE_URL, envInt, jsonHeaders, makeText, parseJson, shortId } from "../../lib/config.js";

const VUS = envInt("VUS", 10);
const DURATION = __ENV.DURATION || "5m";
const BODY_CHARS = envInt("BODY_CHARS", 180);
const SLEEP_SECONDS = Number(__ENV.SLEEP_SECONDS || "0.3");

export const options = {
  scenarios: {
    journey_crud: {
      executor: "constant-vus",
      vus: VUS,
      duration: DURATION,
    },
  },
  thresholds: {
    http_req_failed: ["rate<0.02"],
    "http_req_duration{endpoint:journey_create}": ["p(95)<900", "p(99)<2500"],
    "http_req_duration{endpoint:journey_update}": ["p(95)<900", "p(99)<2500"],
    "http_req_duration{endpoint:journey_list}": ["p(95)<900", "p(99)<2500"],
    "http_req_duration{endpoint:journey_delete}": ["p(95)<900", "p(99)<2500"],
  },
};

export function setup() {
  return { token: getAuthToken() };
}

function journeyPayload(label, bodyChars = BODY_CHARS) {
  return {
    scheduleId: null,
    title: `${label}-${shortId()}`,
    date: "2026-06-25",
    location: "Seoul",
    weatherLabel: "SUNNY",
    moodLabel: "CALM",
    body: makeText(bodyChars, `${label} body`),
    photos: [],
  };
}

export default function (data) {
  const headers = jsonHeaders(data.token);
  let journeyId = null;

  group("journey create", () => {
    const res = http.post(
      `${BASE_URL}/journeys/v2/entries`,
      JSON.stringify(journeyPayload("create")),
      { headers, tags: { endpoint: "journey_create" } },
    );
    const body = parseJson(res, {});
    journeyId = body && body.journey ? body.journey.id : null;

    check(res, {
      "create status 200": (r) => r.status === 200,
      "create returned journey id": () => journeyId !== null && journeyId !== undefined,
    });
  });

  if (journeyId === null || journeyId === undefined) {
    sleep(SLEEP_SECONDS);
    return;
  }

  group("journey list and detail", () => {
    const listRes = http.get(`${BASE_URL}/journeys/v2/entries`, {
      headers,
      tags: { endpoint: "journey_list" },
    });
    check(listRes, {
      "list status 200": (r) => r.status === 200,
    });

    const detailRes = http.get(`${BASE_URL}/journeys/v2/entries/${journeyId}`, {
      headers,
      tags: { endpoint: "journey_detail" },
    });
    check(detailRes, {
      "detail status 200": (r) => r.status === 200,
    });
  });

  group("journey update", () => {
    const res = http.put(
      `${BASE_URL}/journeys/v2/entries/${journeyId}`,
      JSON.stringify(journeyPayload("update")),
      { headers, tags: { endpoint: "journey_update" } },
    );

    check(res, {
      "update status 200": (r) => r.status === 200,
    });
  });

  group("journey stats", () => {
    const res = http.get(`${BASE_URL}/journeys/v2/stats`, {
      headers,
      tags: { endpoint: "journey_stats" },
    });
    check(res, {
      "stats status 200": (r) => r.status === 200,
    });
  });

  group("journey delete", () => {
    const res = http.del(`${BASE_URL}/journeys/v2/entries/${journeyId}`, null, {
      headers,
      tags: { endpoint: "journey_delete" },
    });

    check(res, {
      "delete status 204": (r) => r.status === 204,
    });
  });

  sleep(SLEEP_SECONDS);
}

