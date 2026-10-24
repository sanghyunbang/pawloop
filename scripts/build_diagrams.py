#!/usr/bin/env python3
"""README 의 그림을 만든다 — 밝은 판과 어두운 판을 **한 소스에서** 뽑는다.

## 왜 머메이드를 안 쓰나

깃헙이 머메이드를 렌더해 주기는 한다. 다만 셋이 걸린다.

1. **줄바꿈과 폭을 못 잡는다.** 글자가 길면 상자가 제멋대로 늘고, 좁은 화면에서
   가로로 밀린다. 한글은 특히 잘 터진다.
2. **다크 테마에서 색이 뒤집힌다.** 머메이드 기본 테마는 깃헙 테마를 따라가지만,
   우리가 색으로 뜻을 실으면(예: "서버만 키를 든다") 그 뜻이 테마마다 달라진다.
3. **숫자를 못 싣는다.** 배포 그림처럼 "36.0초 → 0초" 를 눈금 위에 올리려면
   좌표가 필요한데 머메이드는 그 자리를 안 준다.

그래서 SVG 를 직접 쓴다. 깃헙은 저장소 안의 `.svg` 를 `<img>` 로 그대로 보여 준다.

## 왜 생성기인가 — 두 판을 손으로 맞추면 어긋난다

깃헙 다크 테마에서 밝은 그림은 **흰 사각형**으로 뜬다. 해결은 `<picture>` 로 테마별
파일을 주는 것인데, 그러면 같은 그림이 둘이 된다. 손으로 고치면 **한쪽만 고친 채로
넘어간다.**

그래서 모양은 한 번만 쓰고 **색만 갈아 끼운다.** 모양은 CSS 클래스로만 말하고
(`class="card"`), 색은 팔레트가 정한다.

## 쓰는 법

    python3 scripts/build_diagrams.py            # 그려서 저장한다
    python3 scripts/build_diagrams.py --check    # 저장된 것과 다르면 1 로 끝난다

`--check` 는 검사에서 부른다. 그림을 고치고 다시 안 뽑으면 빨간불이다.
"""

from __future__ import annotations

import argparse
import pathlib
import sys
from xml.sax.saxutils import escape

OUT = pathlib.Path(__file__).resolve().parent.parent / "docs" / "diagrams"

# ── 팔레트 ────────────────────────────────────────────────────────────
#
# 밝은 판은 내 웹사이트(betterworldwithlucas.com)의 종이색 계열을 따른다.
# 어두운 판은 깃헙 다크 테마의 캔버스(#0d1117) 위에서 읽히도록 다시 골랐다 —
# 밝은 판의 색을 그대로 어둡게 깔면 오커가 진흙색이 된다.

LIGHT = {
    "bg": "#f7f4ed",      # 바탕
    "card": "#ffffff",    # 상자 안
    "line": "#cdc4b2",    # 가는 테두리
    "ink": "#1f1d1a",     # 본문 글자
    "muted": "#6b6457",   # 설명 글자
    "rule": "#b7ab94",    # 점선·화살표
    "band": "#f1ece1",    # 묶음(그룹) 바탕
    "mineL": "#fbf1dc",   # 우리가 만든 것 — 바탕
    "mine": "#9a6b12",    #            — 테두리·글자
    "keyL": "#e6f2ef",    # 숫자·결과 — 바탕
    "key": "#2f7d74",     #          — 테두리·글자
    "warnL": "#fdecea",   # 끊김·실패 — 바탕
    "warn": "#b3261e",    #          — 테두리·글자
}

DARK = {
    "bg": "#0d1117",
    "card": "#161b22",
    "line": "#30363d",
    "ink": "#e6edf3",
    "muted": "#9198a1",
    "rule": "#484f58",
    "band": "#11161d",
    "mineL": "#2a2113",
    "mine": "#e3b341",
    "keyL": "#0f2b28",
    "key": "#56d4c4",
    "warnL": "#2d1416",
    "warn": "#ff7b72",
}

FONT = ("'Pretendard','Noto Sans KR','Apple SD Gothic Neo',"
        "'Malgun Gothic',system-ui,sans-serif")
MONO = "'SFMono-Regular',Consolas,'Liberation Mono',monospace"


def style(p: dict, scope: str) -> str:
    """색은 여기서만 정한다. 모양 쪽은 클래스 이름만 안다.

    **선택자마다 `scope` 를 앞에 붙인다.** SVG 의 `<style>` 은 문서 전역이라, 두 판을
    한 페이지에 박아 넣으면 뒤엣것이 앞엣것의 `.card` 를 덮는다. 밝은 판 자리에
    어두운 색이 뜨는 식이다 — 미리보기에서 실제로 봤다. 깃헙처럼 `<img>` 로 따로
    부르면 안 겪지만, 어디에 박아도 안전한 쪽이 낫다.
    """
    return f"""
  {scope} .bg{{fill:{p['bg']}}}
  {scope} .band{{fill:{p['band']};stroke:{p['line']};stroke-width:1.5}}
  {scope} .card{{fill:{p['card']};stroke:{p['line']};stroke-width:1.5}}
  {scope} .mine{{fill:{p['mineL']};stroke:{p['mine']};stroke-width:2}}
  {scope} .keyb{{fill:{p['keyL']};stroke:{p['key']};stroke-width:2}}
  {scope} .warnb{{fill:{p['warnL']};stroke:{p['warn']};stroke-width:2}}
  {scope} .idle{{fill:{p['card']};stroke:{p['rule']};stroke-width:1.5;stroke-dasharray:6 5}}
  {scope} .t{{font:600 15px {FONT};fill:{p['ink']}}}
  {scope} .tb{{font:700 16px {FONT};fill:{p['ink']}}}
  {scope} .h{{font:700 13px {FONT};fill:{p['muted']};letter-spacing:.06em}}
  {scope} .s{{font:400 12.5px {FONT};fill:{p['muted']}}}
  {scope} .m{{font:500 12px {MONO};fill:{p['muted']}}}
  {scope} .mine-t{{font:700 15px {FONT};fill:{p['mine']}}}
  {scope} .key-t{{font:700 15px {FONT};fill:{p['key']}}}
  {scope} .key-n{{font:800 26px {FONT};fill:{p['key']}}}
  {scope} .warn-t{{font:700 15px {FONT};fill:{p['warn']}}}
  {scope} .warn-n{{font:800 26px {FONT};fill:{p['warn']}}}
  {scope} .ln{{fill:none;stroke:{p['rule']};stroke-width:1.8}}
  {scope} .ln-key{{fill:none;stroke:{p['key']};stroke-width:2.4}}
  {scope} .ln-warn{{fill:none;stroke:{p['warn']};stroke-width:2.4}}
  {scope} .dash{{fill:none;stroke:{p['rule']};stroke-width:1.5;stroke-dasharray:6 5}}
"""


# ── 그리기 도구 ────────────────────────────────────────────────────────

def rect(x, y, w, h, cls, r=10):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" class="{cls}"/>'


def txt(x, y, s, cls="t", anchor="start"):
    a = f' text-anchor="{anchor}"' if anchor != "start" else ""
    return f'<text x="{x}" y="{y}" class="{cls}"{a}>{escape(s)}</text>'


def line(x1, y1, x2, y2, cls="ln", arrow=True):
    mark = ' marker-end="url(#a)"' if arrow else ""
    return f'<path d="M{x1} {y1} L{x2} {y2}" class="{cls}"{mark}/>'


def elbow(x1, y1, x2, y2, cls="ln"):
    """ㄱ 자로 꺾어 내린다. 가로로 먼저 가고 세로로 내려간다."""
    return (f'<path d="M{x1} {y1} H{x2} V{y2}" class="{cls}" '
            f'marker-end="url(#a)"/>')


def render(name: str, title: str, desc: str, w: int, h: int, body: str, p: dict) -> str:
    """하나를 SVG 문자열로 만든다. `role="img"` 와 desc 로 읽어 주는 도구도 본다."""
    arrow_fill = p["rule"]
    uid = name                      # 파일마다 다르다 — 밝은 판과 어두운 판도 다르다
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" \
width="{w}" height="{h}" id="{uid}" role="img" aria-labelledby="{uid}-t {uid}-d">
<title id="{uid}-t">{escape(title)}</title>
<desc id="{uid}-d">{escape(desc)}</desc>
<defs>
  <marker id="{uid}-a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" \
markerHeight="7" orient="auto-start-reverse">
    <path d="M0 0 L10 5 L0 10 z" fill="{arrow_fill}"/>
  </marker>
</defs>
<style>{style(p, "#" + uid)}</style>
<rect width="{w}" height="{h}" class="bg"/>
{body.replace("url(#a)", f"url(#{uid}-a)")}
</svg>
"""


# ── 그림 1. 시스템 구성 ────────────────────────────────────────────────

ARCH_W, ARCH_H = 920, 690

ARCH_TITLE = "Pawloop 시스템 구성"
ARCH_DESC = (
    "Flutter 앱이 HTTPS 443 으로 EC2 의 Caddy 에 붙는다. Caddy 는 같은 EC2 안의 "
    "Spring Boot 두 벌(app-blue · app-green) 앞에 서고, 평소에는 한 벌만 돈다. "
    "Spring Boot 는 같은 EC2 의 MySQL 컨테이너(데이터는 별도 EBS)와 S3 를 쓰고, "
    "공공데이터·OpenAI·푸시·소셜 로그인은 서버만 키를 들고 부른다. "
    "운영 설정은 부팅 때 SSM 파라미터에서 받는다."
)


def arch_body() -> str:
    o = []
    A = o.append
    A(txt(40, 40, "시스템 구성", "tb"))
    A(txt(40, 62, "앱은 키를 들지 않는다 · 계약은 openapi.yaml 하나", "s"))

    # ── 앱 ──
    A(rect(40, 84, 540, 108, "band"))
    A(txt(56, 106, "사용자 기기", "h"))
    A(rect(56, 116, 508, 62, "mine"))
    A(txt(72, 140, "Flutter 앱", "mine-t"))
    for i, (lbl, sub) in enumerate([
            ("v2/screens", "화면"), ("v2/domain", "순수 규칙"),
            ("v2/data", "저장소·정책"), ("AuthedClient", "401 자동 갱신")]):
        x = 176 + i * 98
        A(txt(x, 136, lbl, "m"))
        A(txt(x, 154, sub, "s"))

    # 앱 → 서버
    A(line(310, 192, 310, 236, "ln"))
    A(txt(322, 214, "HTTPS 443", "m"))

    # ── EC2 ──
    A(rect(40, 240, 540, 392, "band"))
    A(txt(56, 262, "AWS EC2 · t3.medium", "h"))

    A(rect(56, 274, 508, 54, "card"))
    A(txt(72, 299, "Caddy", "t"))
    A(txt(72, 317, "TLS 종료 · 앞단 하나", "s"))
    A(txt(548, 299, ":443", "m", "end"))
    A(txt(548, 317, "lb_policy first · health 3초", "s", "end"))

    # Caddy → 두 벌
    A(elbow(180, 328, 180, 362, "ln"))
    A(elbow(440, 328, 440, 362, "dash"))

    A(rect(56, 366, 248, 86, "mine"))
    A(txt(72, 390, "app-blue", "mine-t"))
    A(txt(72, 410, "Spring Boot 3.5.4 · Java 21", "s"))
    A(txt(72, 428, "지금 서비스 중", "s"))

    A(rect(316, 366, 248, 86, "idle"))
    A(txt(332, 390, "app-green", "t"))
    A(txt(332, 410, "같은 이미지, 다음 판", "s"))
    A(txt(332, 428, "평소에는 꺼져 있다", "s"))

    # 모듈 띠
    A(rect(56, 462, 508, 46, "card"))
    A(txt(72, 481, "Spring Modulith 경계 — 22개 중 도메인 7", "h"))
    mods = "chat · walk · community · place · schedule · moderation · family"
    A(txt(72, 500, mods, "m"))

    # MySQL
    A(line(180, 508, 180, 542, "ln"))
    A(rect(56, 546, 508, 66, "card"))
    A(txt(72, 572, "MySQL 8", "t"))
    A(txt(72, 592, "경로는 LINESTRING · 장소는 0.02° 격자 캐시", "s"))
    A(txt(548, 572, "같은 EC2 · 컨테이너", "s", "end"))
    A(txt(548, 592, "데이터는 별도 EBS (/mnt/data)", "s", "end"))

    # ── 바깥 ──
    A(rect(610, 84, 270, 548, "band"))
    A(txt(626, 106, "바깥 — 서버만 키를 들고 부른다", "h"))

    outs = [
        ("S3", "사진·영상. 좌표와 EXIF 는", "기기에서 지우고 올린다", "card"),
        ("공공데이터", "관광공사 · 행정안전부 · 두루누비", "키는 서버에만 있다", "mine"),
        ("OpenAI", "주간 요약 두 문장", "규칙 문장이 먼저 뜬다", "card"),
        ("FCM · SES", "푸시와 메일", "", "card"),
        ("소셜 로그인", "구글 · 카카오 · 네이버 · 애플", "", "card"),
        ("SSM 파라미터", "운영 .env 정본", "부팅 때 받아 간다", "mine"),
    ]
    y = 116
    for name, l1, l2, cls in outs:
        hh = 78 if l2 else 62
        A(rect(626, y, 238, hh, cls))
        A(txt(642, y + 24, name, "mine-t" if cls == "mine" else "t"))
        A(txt(642, y + 44, l1, "s"))
        if l2:
            A(txt(642, y + 62, l2, "s"))
        y += hh + 10

    # 서버 → 바깥. **모듈 띠에서** 나간다 — app-green 은 평소에 꺼져 있으므로
    # 거기서 선을 빼면 "꺼진 것이 외부를 부른다" 로 읽힌다.
    A('<path d="M564 485 H592 V250 H622" class="dash" marker-end="url(#a)"/>')
    A('<path d="M564 485 H592 V560 H622" class="dash" marker-end="url(#a)"/>')
    # 글자는 안 붙인다 — EC2 와 바깥 사이가 30px 뿐이라 선 위에 겹친다.
    # 그 말은 "바깥" 제목에 실었다.

    # 범례
    A(rect(40, 648, 16, 16, "mine", 4))
    A(txt(64, 661, "우리가 만든 것 · 키를 드는 곳", "s"))
    A(rect(300, 648, 16, 16, "idle", 4))
    A(txt(324, 661, "평소에는 꺼져 있다", "s"))
    return "\n".join(o)


# ── 그림 2. 배포 ──────────────────────────────────────────────────────

DEP_W, DEP_H = 920, 560

DEP_TITLE = "배포 중 끊김 — 전과 후"
DEP_DESC = (
    "전에는 docker compose up -d 한 줄로 배포했고 평균 35.2초가 끊겼다. "
    "그 36초의 98퍼센트는 포트는 열렸는데 스프링이 아직 부팅 중인 구간이었다. "
    "후에는 쉬는 쪽을 새 이미지로 띄우고 healthy 가 된 것을 확인한 뒤 옛 쪽을 내린다. "
    "배포에 걸리는 시간은 44초로 늘었지만 그동안 사용자는 옛 쪽을 쓰고 있어서 "
    "끊김은 0초, 실패는 표본 600건 중 0건이다."
)


def dep_body() -> str:
    o = []
    A = o.append
    A(txt(40, 40, "배포 중 끊김 — 전과 후", "tb"))
    A(txt(40, 62, "스테이징 · 서버 내부에서 0.2초 간격 600회 측정 · 2026-10-22  (운영 수치는 README 표)", "s"))

    L, R = 40, 700           # 눈금 왼쪽 / 오른쪽
    def tx(sec, span):       # 초 → x 좌표
        return L + (R - L) * sec / span

    # ── 전 ──
    A(rect(40, 84, 840, 186, "band"))
    A(txt(56, 108, "전 — docker compose up -d", "h"))
    A(txt(56, 132, "옛 것을 내리고 새 것을 올린다. 그 사이가 통째로 빈다.", "s"))

    span = 48
    y0 = 152
    # 옛 앱
    A(rect(L, y0, tx(6, span) - L, 30, "card", 6))
    A(txt(L + 12, y0 + 20, "옛 앱", "s"))
    # 끊김
    A(rect(tx(6, span), y0, tx(42, span) - tx(6, span), 30, "warnb", 6))
    A(txt((tx(6, span) + tx(42, span)) / 2, y0 + 20, "끊김", "warn-t", "middle"))
    # 새 앱
    A(rect(tx(42, span), y0, R - tx(42, span), 30, "card", 6))
    A(txt(tx(42, span) + 12, y0 + 20, "새 앱", "s"))

    # 끊김 안쪽 사정
    A(f'<path d="M{tx(6,span)} {y0+42} H{tx(42,span)}" class="ln-warn" marker-end="none"/>')
    A(txt((tx(6, span) + tx(42, span)) / 2, y0 + 62,
          "98% 가 curl 56 — 포트는 열렸는데 스프링이 아직 부팅 중", "s", "middle"))
    A(txt((tx(6, span) + tx(42, span)) / 2, y0 + 80,
          "끄는 쪽을 아무리 빨리 해도 안 줄어든다", "s", "middle"))

    A(rect(724, 148, 156, 92, "warnb"))
    A(txt(802, 186, "35.2초", "warn-n", "middle"))
    A(txt(802, 208, "평균 끊김 (4회)", "s", "middle"))
    A(txt(802, 226, "실패 154건 / 600", "s", "middle"))

    # ── 후 ──
    A(rect(40, 286, 840, 196, "band"))
    A(txt(56, 310, "후 — deploy-bluegreen.sh", "h"))
    A(txt(56, 334, "쉬는 쪽을 먼저 띄우고, healthy 를 확인한 뒤에 옛 쪽을 내린다.", "s"))

    y1 = 356
    # blue (서비스 중) — 끝까지 가다가 green 이 뜬 뒤 끊는다
    A(rect(L, y1, tx(44, span) - L, 30, "card", 6))
    A(txt(L + 12, y1 + 20, "app-blue — 사용자는 내내 이쪽을 쓴다", "s"))

    # green 부팅 → healthy → 서빙
    y2 = y1 + 40
    A(rect(tx(4, span), y2, tx(44, span) - tx(4, span), 30, "idle", 6))
    A(txt(tx(4, span) + 12, y2 + 20, "app-green 부팅 중", "s"))
    A(rect(tx(44, span), y2, R - tx(44, span), 30, "mine", 6))
    A(txt(tx(44, span) + 12, y2 + 20, "서빙", "mine-t"))

    # healthy 표시
    A(f'<path d="M{tx(44,span)} {y1 - 4} V{y2 + 38}" class="ln-key" marker-end="none"/>')
    A(txt(tx(44, span) - 10, y1 - 12, "healthy 확인 → 여기서 바꾼다", "key-t", "end"))

    A(rect(724, 350, 156, 112, "keyb"))
    A(txt(802, 390, "0초", "key-n", "middle"))
    A(txt(802, 412, "끊김", "s", "middle"))
    A(txt(802, 432, "실패 0건 / 600", "s", "middle"))
    A(txt(802, 450, "양방향 2회 모두", "s", "middle"))

    # 아래 설명
    A(txt(40, 508, "배포에 걸리는 시간은 11초 → 44초로 늘었다. 맞바꾼 값이다 — "
                   "그 44초 동안 사용자는 옛 쪽을 쓰고 있다.", "s"))
    A(txt(40, 530, "겹치는 동안 로그인 코드가 인메모리라 그때 로그인 중이던 사람은 "
                   "다시 시도해야 한다(이슈 #792). 전에는 그 시간 동안 전부 끊겼다.", "s"))
    return "\n".join(o)


# ── 내보내기 ──────────────────────────────────────────────────────────

DIAGRAMS = [
    ("architecture", ARCH_TITLE, ARCH_DESC, ARCH_W, ARCH_H, arch_body),
    ("deploy", DEP_TITLE, DEP_DESC, DEP_W, DEP_H, dep_body),
]


def build() -> dict[pathlib.Path, str]:
    out = {}
    for name, title, desc, w, h, body in DIAGRAMS:
        shapes = body()
        for suffix, palette in (("", LIGHT), ("-dark", DARK)):
            out[OUT / f"{name}{suffix}.svg"] = render(
                f"{name}{suffix}", title, desc, w, h, shapes, palette)
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true",
                    help="저장된 것과 다르면 1 로 끝낸다")
    args = ap.parse_args()

    files = build()
    if args.check:
        stale = [p for p, s in files.items()
                 if not p.exists() or p.read_text(encoding="utf-8") != s]
        if stale:
            print("그림이 생성기와 어긋난다. `python3 scripts/build_diagrams.py` 를 "
                  "돌리고 결과를 커밋해라:", file=sys.stderr)
            for p in stale:
                print(f"  {p.relative_to(OUT.parent.parent)}", file=sys.stderr)
            return 1
        print(f"그림 {len(files)}개 — 생성기와 같다")
        return 0

    OUT.mkdir(parents=True, exist_ok=True)
    for p, s in files.items():
        p.write_text(s, encoding="utf-8")
        print(f"  {p.relative_to(OUT.parent.parent)}  {len(s):,}바이트")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
