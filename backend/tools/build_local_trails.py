# backend/tools/build_local_trails.py
#
# 동네 길 자산을 만든다 — 이슈 #346.
#
# ## 왜 스크립트인가 (API 를 안 부르는 이유)
#
# 원본은 전국길관광정보표준데이터(공공데이터포털 15017321)다. 196개 지자체가 올린 것을
# 포털이 매월 병합하고, **갱신주기는 "연간"** 이다. 1년에 한 번 바뀌는 값을 매달 API 로
# 부를 이유가 없다 — 행정동 목록(#342)에서 내린 것과 같은 판단이다.
#
# 그래서 한 번 받아 좌표를 붙여 결과를 커밋한다. 그러면 활용신청도, 런타임 외부 호출도,
# 그 호출이 죽는 날의 빈 지도도 없다.
#
# ## 왜 좌표를 붙여야 하나
#
# **원본에 위도·경도가 없다.** 항목은 길명·길소개·총길이·총소요시간·시작/종료 지점의
# 이름과 주소·경로정보·관리기관뿐이고, 위치는 전부 **주소 문자열**이다. `경로정보` 도
# 선 좌표가 아니라 `산수교→월성마을→황점마을` 꼴의 글이다.
#
# 그래서 시작지점 주소를 지오코더에 넣어 좌표로 바꾼다. 지오코더는 갈아끼울 수 있게
# 함수 하나로 뒀다 — 카카오 이용약관이 "네이버 지도 위에 쓰는 것" 을 막으면
# 주소기반산업지원서비스(juso.go.kr)로 바꾼다.
#
# ## 출처
#
#   전국길관광정보표준데이터 — 공공데이터포털 15017321 (제공기관: 지방자치단체 196곳)
#
# 표준데이터 상세에는 **공공누리 유형 표기가 없다**(2026-09-08 확인). 포털의 일반
# 이용정책을 따르는 것으로 보지만 확정된 사실이 아니라, 문서의 이용허락 표에 그대로
# 적어 뒀다. 확인되면 그 표와 이 머리말을 함께 고친다.
#
# ## 쓰는 법
#
#   # 1. 원본을 받는다 (로그인·활용신청 없이 받아진다 — 파일/그리드 다운로드다)
#   #    브라우저에서 https://www.data.go.kr/data/15017321/standard.do 의 CSV/JSON 다운로드,
#   #    또는 그 페이지가 쓰는 주소를 그대로:
#   curl -o gil.json 'https://www.data.go.kr/download/standard.json?publicDataPk=15017321&…'
#
#   # 2. 좌표를 붙여 자산을 만든다 (backend/.env 의 KAKAO_REST_API_KEY 를 읽는다)
#   python backend/tools/build_local_trails.py gil.json \
#          backend/src/main/resources/data/local_trails.json
#
# 1,346행이면 지오코딩에 4~5분쯤 걸린다. 이미 만든 자산이 있으면 **그 좌표를 재사용**하고
# 새 길만 물어본다 — 다시 돌릴 때 처음부터 하지 않는다.
import hashlib
import io
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

SOURCE_LABEL = "전국길관광정보표준데이터 · 공공데이터포털 15017321"
GEOCODER = "kakao-local-address"


def env(name, path="backend/.env"):
    """`.env` 에서 이름 하나를 읽는다. 주석으로 내려 둔 줄도 읽는다."""
    if not os.path.isfile(path):
        return ""
    for line in io.open(path, encoding="utf-8"):
        s = line.strip().lstrip("#").strip()
        if s.startswith(name + "="):
            return s.split("=", 1)[1].strip()
    return ""


def geocode(addr, key):
    """주소 하나를 (위도, 경도) 로. 못 찾으면 None."""
    url = "https://dapi.kakao.com/v2/local/search/address.json?query=" + urllib.parse.quote(addr)
    req = urllib.request.Request(url, headers={"Authorization": "KakaoAK " + key})
    with urllib.request.urlopen(req, timeout=15) as r:
        docs = json.loads(r.read().decode("utf-8")).get("documents", [])
    if not docs:
        return None
    return round(float(docs[0]["y"]), 6), round(float(docs[0]["x"]), 6)


def trail_id(name, addr, km, mins):
    """안정적인 키. 원본에 식별자가 없어 값 몇을 이어 붙여 만든다.

    이름만 쓰면 `문화유산여행길(1코스)` 같은 것이 지자체를 넘어 겹친다. 이름+주소도
    모자란다 — 창녕군의 `우포늪생명길` 은 **같은 이름·같은 시작점**으로 9.7 · 8.4 · 2.5 ·
    1.0km 네 코스가 올라와 있다. 길이와 소요시간까지 넣어야 넷이 살아남는다.
    """
    seed = "|".join([(name or "").strip(), (addr or "").strip(), str(km), str(mins)])
    return "localtrail:" + hashlib.sha1(seed.encode("utf-8")).hexdigest()[:12]


def length_km(raw):
    """`총길이` 는 문자열이고 단위가 섞여 있다(`5.9`, `2`, `17.7`)."""
    try:
        v = float(str(raw).strip())
    except (TypeError, ValueError):
        return None
    return v if 0 < v < 1000 else None


def minutes(raw):
    """`4시간`, `1시간 30분`, `40분` 을 분으로. 못 읽으면 None — 지어내지 않는다."""
    s = str(raw or "").strip()
    if not s:
        return None
    hours = re.search(r"(\d+)\s*시간", s)
    mins = re.search(r"(\d+)\s*분", s)
    if not hours and not mins:
        return None
    total = (int(hours.group(1)) * 60 if hours else 0) + (int(mins.group(1)) if mins else 0)
    return total or None


def trustworthy_length(km, mins):
    """길이와 소요시간이 서로 말이 되는가.

    원본은 지자체가 손으로 적은 값이라 단위가 틀린 행이 있다 — `한류스타거리` 는
    총길이 `108`, 소요시간 `30분` 이다. 그대로 쓰면 카드에 `108km · 약 30분` 이 뜨고,
    그건 시속 216km 다. 사람의 걸음은 시속 4km 쯤이라 **12km/h 를 넘으면 길이를 버린다** —
    지어내지 않고 그 줄만 비운다. 소요시간은 그대로 둔다.
    """
    if km is None or not mins:
        return km
    return None if km / (mins / 60.0) > 12 else km


def start_addresses(row):
    """시작지점 주소를 **둘 다** 준다 — 도로명이 먼저다.

    도로명이 지오코더에 없는 경우가 실제로 있다(`안산시 잘푸리길 109`). 그때 지번으로
    한 번 더 물어보면 대개 찾는다. 처음에는 도로명 하나만 물어 1,346 중 75개를 놓쳤다.
    """
    road = (row.get("BEGIN_RDNMADR") or "").strip()
    lot = (row.get("BEGIN_LNMADR") or "").strip()
    return [a for a in (road, lot) if a]


def start_address(row):
    """카드에 적을 대표 주소."""
    got = start_addresses(row)
    return got[0] if got else ""


def district(addr):
    """`서울특별시 성동구 …` → `서울특별시 성동구`. 카드에 보여 줄 만큼만."""
    parts = (addr or "").split()
    return " ".join(parts[:2]) if len(parts) >= 2 else (addr or "")


def load_previous(path):
    """이미 만든 자산의 좌표. 다시 돌릴 때 같은 주소를 또 묻지 않는다."""
    if not os.path.isfile(path):
        return {}
    try:
        old = json.loads(io.open(path, encoding="utf-8").read())
    except ValueError:
        return {}
    return {t["id"]: (t["lat"], t["lng"]) for t in old.get("trails", []) if t.get("lat")}


def main(src_path, out_path):
    key = env("KAKAO_REST_API_KEY")
    if not key:
        sys.exit("KAKAO_REST_API_KEY 를 backend/.env 에서 못 읽었다 — 주석 처리돼 있어도 읽는다.")

    rows = json.loads(io.open(src_path, encoding="utf-8").read())
    known = load_previous(out_path)
    print("원본 %d행 · 이미 아는 좌표 %d개" % (len(rows), len(known)))

    trails = []
    asked = reused = failed = 0
    for i, row in enumerate(rows, 1):
        name = (row.get("STRET_NM") or "").strip()
        addr = start_address(row)
        if not name or not addr:
            failed += 1
            continue

        km = trustworthy_length(length_km(row.get("STRET_LT")), minutes(row.get("REQRE_TIME")))
        mins = minutes(row.get("REQRE_TIME"))
        tid = trail_id(name, addr, km, mins)
        point = known.get(tid)
        if point:
            reused += 1
        else:
            for candidate in start_addresses(row):
                try:
                    point = geocode(candidate, key)
                    asked += 1
                    time.sleep(0.05)
                except Exception as e:  # noqa: BLE001 — 어떤 실패든 다음 주소로 넘어간다
                    print("  지오코딩 실패(%s): %s" % (e.__class__.__name__, name[:20]))
                    point = None
                if point:
                    break
        if not point:
            failed += 1
            continue

        trails.append({
            "id": tid,
            "name": name,
            "lat": point[0],
            "lng": point[1],
            "addr": district(addr),
            "lengthKm": km,
            "minutes": mins,
            "intro": (row.get("STRET_INTRCN") or "").strip() or None,
            "waypoints": (row.get("COURS_INFO") or "").strip() or None,
            "org": (row.get("INSTITUTION_NM") or "").strip() or None,
            "tel": (row.get("PHONE_NUMBER") or "").strip() or None,
        })
        if i % 200 == 0:
            print("  %d/%d …" % (i, len(rows)))

    trails.sort(key=lambda t: (t["addr"], t["name"]))
    asset = {
        "version": max((r.get("REFERENCE_DATE") or "") for r in rows) or "unknown",
        "source": SOURCE_LABEL,
        "geocoder": GEOCODER,
        "trails": trails,
    }
    io.open(out_path, "w", encoding="utf-8", newline="\n").write(
        json.dumps(asset, ensure_ascii=False, separators=(",", ":")) + "\n")

    lengths = sorted(t["lengthKm"] for t in trails if t["lengthKm"])
    print()
    print("담은 길 %d개 · 새로 물어본 주소 %d · 재사용 %d · 못 담음 %d"
          % (len(trails), asked, reused, failed))
    if lengths:
        print("길이 중앙값 %.1fkm · 5km 이하 %d개 · 10km 이하 %d개"
              % (lengths[len(lengths) // 2],
                 sum(1 for x in lengths if x <= 5),
                 sum(1 for x in lengths if x <= 10)))
    print("→ %s (%.0fKB)" % (out_path, os.path.getsize(out_path) / 1024))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("쓰는 법: python backend/tools/build_local_trails.py <원본.json> <자산.json>")
    main(sys.argv[1], sys.argv[2])
