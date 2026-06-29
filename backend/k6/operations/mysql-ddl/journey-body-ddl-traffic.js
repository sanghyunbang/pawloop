import http from "k6/http";
import { check, group, sleep } from "k6";
import { getAuthToken } from "../../lib/auth.js";
import { BASE_URL, envInt, jsonHeaders, makeText, parseJson, shortId } from "../../lib/config.js";

const VUS = envInt("VUS", 20);
const DURATION = __ENV.DURATION || "15m";
const BODY_CHARS = envInt("BODY_CHARS", 180);
const SLEEP_SECONDS = Number(__ENV.SLEEP_SECONDS || "0.2");

export const options = {
  scenarios: {
    journey_body_ddl_traffic: {
      executor: "constant-vus",
      vus: VUS,
      duration: DURATION,
    },
  },
  thresholds: {
    http_req_failed: ["rate<0.05"],
    "http_req_duration{endpoint:ddl_journey_create}": ["p(95)<1200", "p(99)<4000"],
    "http_req_duration{endpoint:ddl_journey_update}": ["p(95)<1200", "p(99)<4000"],
    "http_req_duration{endpoint:ddl_journey_list}": ["p(95)<1200", "p(99)<4000"],
  },
};

export function setup() {
  const token = getAuthToken();
  const headers = jsonHeaders(token);
  const res = http.post(
    `${BASE_URL}/journeys/v2/entries`,
    JSON.stringify(payload("seed", Math.min(BODY_CHARS, 180))),
    { headers, tags: { endpoint: "ddl_journey_seed_create" } },
  );
  const body = parseJson(res, {});
  const seedId = body && body.journey ? body.journey.id : null;

  if (seedId === null || seedId === undefined) {
    throw new Error(`Failed to create DDL traffic seed journey. status=${res.status} body=${res.body}`);
  }

  return { token, seedId };
}

export function teardown(data) {
  if (!data || data.seedId === null || data.seedId === undefined) {
    return;
  }

  http.del(`${BASE_URL}/journeys/v2/entries/${data.seedId}`, null, {
    headers: jsonHeaders(data.token),
    tags: { endpoint: "ddl_journey_seed_delete" },
  });
}

function payload(label, bodyChars = BODY_CHARS) {
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

function createUpdateDelete(headers) {
  const createRes = http.post(
    `${BASE_URL}/journeys/v2/entries`,
    JSON.stringify(payload("ddl-create")),
    { headers, tags: { endpoint: "ddl_journey_create" } },
  );
  const body = parseJson(createRes, {});
  const id = body && body.journey ? body.journey.id : null;

  check(createRes, {
    "ddl create status 200": (r) => r.status === 200,
    "ddl create returned id": () => id !== null && id !== undefined,
  });

  if (id === null || id === undefined) {
    return;
  }

  const updateRes = http.put(
    `${BASE_URL}/journeys/v2/entries/${id}`,
    JSON.stringify(payload("ddl-update")),
    { headers, tags: { endpoint: "ddl_journey_update" } },
  );
  check(updateRes, {
    "ddl update status 200": (r) => r.status === 200,
  });

  const deleteRes = http.del(`${BASE_URL}/journeys/v2/entries/${id}`, null, {
    headers,
    tags: { endpoint: "ddl_journey_delete" },
  });
  check(deleteRes, {
    "ddl delete status 204": (r) => r.status === 204,
  });
}

export default function (data) {
  const headers = jsonHeaders(data.token);
  const r = Math.random();

  if (r < 0.45) {
    group("ddl journey write traffic", () => createUpdateDelete(headers));
  } else if (r < 0.75) {
    group("ddl journey list traffic", () => {
      const res = http.get(`${BASE_URL}/journeys/v2/entries`, {
        headers,
        tags: { endpoint: "ddl_journey_list" },
      });
      check(res, {
        "ddl list status 200": (response) => response.status === 200,
      });
    });
  } else {
    group("ddl journey detail traffic", () => {
      const res = http.get(`${BASE_URL}/journeys/v2/entries/${data.seedId}`, {
        headers,
        tags: { endpoint: "ddl_journey_detail" },
      });
      check(res, {
        "ddl detail status 200": (response) => response.status === 200,
      });
    });
  }

  sleep(SLEEP_SECONDS);
}

