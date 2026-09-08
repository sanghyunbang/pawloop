# backend/tools/build_playgrounds.py
#
# 반려견 놀이터 자산을 만든다 — 이슈 #346.
#
# ## 왜 지자체 파일을 모으나
#
# **전국 표준데이터가 없다.** 공공데이터포털에서 "반려견 놀이터" 로 찾으면 시·군·구가
# 각자 올린 파일이 나온다(고양·성남·파주·동대문구·서초구·미추홀구·계양구 등). 전국을
# 한 API 로 주는 곳이 없어서, 파일을 하나씩 받아 여기서 합친다.
#
# 파일은 **로그인도 활용신청도 없이** 페이지의 `다운로드` 버튼으로 받는다. 다만 그
# 버튼이 브라우저 세션을 요구해 스크립트로는 못 받는다 — 사람이 눌러 `backend/tools/data/`
# 아래 두면 이 스크립트가 합친다.
#
# ## 컬럼이 파일마다 다르다
#
# 고양시는 `시설명,도로명주소,지번주소,위도,경도,관리기관,전화번호,데이터기준일` 이다.
# 다른 지자체는 이름이 조금씩 다르므로 **여러 후보 이름을 훑어** 찾는다. 못 찾으면 그
# 파일을 건너뛰고 무엇이 없었는지 찍는다 — 조용히 빈 자산을 만들지 않는다.
#
# ## 좌표가 있는 파일만 쓴다
#
# 위도·경도가 없는 파일은 주소만 있는데, 놀이터는 수가 적어 지오코딩까지 붙일 값이
# 아니다. 그런 파일은 건너뛰고 이름을 찍는다(동네 길과 다른 판단이다 — 그쪽은 1,346개였다).
#
# ## 쓰는 법
#
#   # 1. 포털에서 CSV 를 받아 backend/tools/data/ 아래 둔다 (이름은 아무거나)
#   # 2. 합친다
#   python backend/tools/build_playgrounds.py \
#          backend/tools/data backend/src/main/resources/data/playgrounds.json
import csv
import glob
import hashlib
import io
import json
import os
import sys

SOURCE_LABEL = "지자체 반려견 놀이터 현황 · 공공데이터포털"

# 파일마다 이름이 다르다. 앞에 있는 것부터 찾는다.
COLUMNS = {
    "name": ["시설명", "놀이터명", "명칭", "공원명", "시설명칭", "반려견놀이터명"],
    "road": ["도로명주소", "소재지도로명주소", "주소"],
    "lot": ["지번주소", "소재지지번주소"],
    "lat": ["위도", "latitude", "LAT", "y좌표"],
    "lng": ["경도", "longitude", "LON", "LOT", "x좌표"],
    "org": ["관리기관", "관리기관명", "운영기관"],
    "tel": ["전화번호", "관리기관전화번호", "연락처"],
    "date": ["데이터기준일", "데이터기준일자"],
}


def pick(row, key):
    """행에서 [key] 에 해당하는 값을 찾는다. 없으면 빈 문자열."""
    for candidate in COLUMNS[key]:
        for column, value in row.items():
            if column and column.strip().lower() == candidate.lower():
                return (value or "").strip()
    return ""


def number(raw):
    try:
        return round(float(str(raw).strip()), 6)
    except (TypeError, ValueError):
        return None


def district(addr):
    """`경기도 고양시 일산서구 …` → `경기도 고양시`. 카드에 보여 줄 만큼만."""
    parts = (addr or "").split()
    return " ".join(parts[:2]) if len(parts) >= 2 else (addr or "")


def playground_id(name, lat, lng):
    """이름 + 좌표. 같은 이름이 시를 넘어 겹친다(`반려견 놀이터` 는 흔한 이름이다)."""
    seed = "%s|%.5f|%.5f" % ((name or "").strip(), lat, lng)
    return "playground:" + hashlib.sha1(seed.encode("utf-8")).hexdigest()[:12]


def read_csv(path):
    """한 파일의 놀이터들. 좌표가 없거나 컬럼을 못 찾으면 빈 목록 + 이유."""
    # 포털 CSV 는 cp949 인 것이 흔하다. utf-8 로 먼저 열고 실패하면 cp949 로.
    for encoding in ("utf-8-sig", "utf-8", "cp949"):
        try:
            text = io.open(path, encoding=encoding).read()
            break
        except UnicodeDecodeError:
            continue
    else:
        return [], "인코딩을 못 읽었다"

    rows = list(csv.DictReader(io.StringIO(text)))
    if not rows:
        return [], "행이 없다"

    found = []
    for row in rows:
        name = pick(row, "name")
        lat, lng = number(pick(row, "lat")), number(pick(row, "lng"))
        if not name:
            continue
        if lat is None or lng is None:
            return [], "위도·경도 컬럼이 없다 — 주소만 있는 파일은 아직 안 쓴다"
        addr = pick(row, "road") or pick(row, "lot")
        found.append({
            "id": playground_id(name, lat, lng),
            "name": name,
            "lat": lat,
            "lng": lng,
            "addr": district(addr),
            "fullAddr": addr or None,
            "org": pick(row, "org") or None,
            "tel": pick(row, "tel") or None,
            "asOf": pick(row, "date") or None,
        })
    return found, None


def main(src_dir, out_path):
    files = sorted(glob.glob(os.path.join(src_dir, "*.csv")))
    if not files:
        sys.exit("CSV 가 하나도 없다: " + src_dir)

    places, skipped = [], []
    for path in files:
        found, why = read_csv(path)
        label = os.path.basename(path)
        if why:
            skipped.append("%s — %s" % (label, why))
            continue
        print("  %-34s %d곳" % (label, len(found)))
        places.extend(found)

    # 같은 놀이터가 두 파일에 있을 수 있다(도 파일 + 시 파일).
    unique = {}
    for p in places:
        unique.setdefault(p["id"], p)
    out = sorted(unique.values(), key=lambda p: (p["addr"], p["name"]))

    asset = {
        "version": max((p.get("asOf") or "") for p in out) or "unknown",
        "source": SOURCE_LABEL,
        "playgrounds": out,
    }
    io.open(out_path, "w", encoding="utf-8", newline="\n").write(
        json.dumps(asset, ensure_ascii=False, separators=(",", ":")) + "\n")

    print()
    print("담은 놀이터 %d곳 (중복 %d 제거) · 파일 %d개"
          % (len(out), len(places) - len(out), len(files) - len(skipped)))
    for s in skipped:
        print("  건너뜀 — %s" % s)
    print("→ %s (%.1fKB)" % (out_path, os.path.getsize(out_path) / 1024))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("쓰는 법: python backend/tools/build_playgrounds.py <CSV 디렉터리> <자산.json>")
    main(sys.argv[1], sys.argv[2])
