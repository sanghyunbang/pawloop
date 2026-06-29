import http from "k6/http";
import { check, group, sleep } from "k6";
import { BASE_URL, envInt, parseJson } from "../../lib/config.js";

const VUS = envInt("VUS", 20);
const DURATION = __ENV.DURATION || "5m";
const SLEEP_SECONDS = Number(__ENV.SLEEP_SECONDS || "0.2");

export const options = {
  scenarios: {
    explore_read_baseline: {
      executor: "constant-vus",
      vus: VUS,
      duration: DURATION,
    },
  },
  thresholds: {
    http_req_failed: ["rate<0.01"],
    "http_req_duration{endpoint:explore_list}": ["p(95)<700", "p(99)<2000"],
    "http_req_duration{endpoint:explore_scroll}": ["p(95)<700", "p(99)<2000"],
    "http_req_duration{endpoint:explore_search}": ["p(95)<900", "p(99)<2500"],
  },
};

export function setup() {
  const res = http.get(`${BASE_URL}/api/explore/places?page=0&size=20`, {
    tags: { endpoint: "explore_setup_list" },
  });
  const body = parseJson(res, {});
  const ids = (body.content || [])
    .map((item) => item.contentid)
    .filter((id) => id !== undefined && id !== null);

  return { ids };
}

export default function (data) {
  group("explore list", () => {
    const page = Math.floor(Math.random() * envInt("MAX_PAGE", 20));
    const res = http.get(`${BASE_URL}/api/explore/places?page=${page}&size=20`, {
      tags: { endpoint: "explore_list" },
    });

    check(res, {
      "list status 200": (r) => r.status === 200,
      "list body json": (r) => parseJson(r) !== null,
    });
  });

  group("explore scroll", () => {
    let cursor = "";
    for (let i = 0; i < envInt("SCROLL_PAGES", 2); i += 1) {
      const query = cursor
        ? `/api/explore/places/scroll?size=20&cursor=${encodeURIComponent(cursor)}`
        : "/api/explore/places/scroll?size=20";
      const res = http.get(`${BASE_URL}${query}`, {
        tags: { endpoint: "explore_scroll" },
      });

      const body = parseJson(res, {});
      check(res, {
        "scroll status 200": (r) => r.status === 200,
        "scroll body json": () => body !== null,
      });

      cursor = body.nextCursor || "";
      if (!cursor) {
        break;
      }
    }
  });

  group("explore search", () => {
    const queries = (__ENV.SEARCH_QUERIES || "서울,부산,카페,바다").split(",");
    const q = queries[Math.floor(Math.random() * queries.length)].trim();
    const res = http.get(
      `${BASE_URL}/api/explore/places/search?q=${encodeURIComponent(q)}&page=0&size=20`,
      { tags: { endpoint: "explore_search" } },
    );

    check(res, {
      "search status 200": (r) => r.status === 200,
      "search body json": (r) => parseJson(r) !== null,
    });
  });

  if (data.ids && data.ids.length > 0 && Math.random() < 0.4) {
    const id = data.ids[Math.floor(Math.random() * data.ids.length)];
    const res = http.get(`${BASE_URL}/api/explore/places/${id}`, {
      tags: { endpoint: "explore_detail" },
    });

    check(res, {
      "detail status 200 or 404": (r) => r.status === 200 || r.status === 404,
    });
  }

  sleep(SLEEP_SECONDS);
}

