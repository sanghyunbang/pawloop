# app/tool/build_regions.py
#
# 행정동 목록 자산을 만든다 — 이슈 #342.
#
# ## 왜 스크립트인가
#
# 원본은 34MB 짜리 경계 GeoJSON 이다. 앱에 넣을 수 없고, 넣을 필요도 없다 — 우리에게
# 필요한 것은 **이름·코드·중심점** 뿐이다. 그래서 원본을 받아 그 셋만 뽑는다.
#
# 결과물(`app/assets/regions/hangjeongdong.json`)은 저장소에 커밋한다. 빌드 때 받지 않는
# 이유는 그 순간 인터넷이 없으면 앱이 못 나오기 때문이다.
#
# ## 출처와 라이선스 (지켜야 한다)
#
#   원자료: 통계청 SGIS 행정동 경계 — 공공누리 제1유형(출처표시)
#   가공본: https://github.com/vuski/admdongkor — CC BY 4.0
#
# CC BY 4.0 은 **파생물에도 출처 표시 의무가 남는다.** 그래서 결과 JSON 의 머리에 출처를
# 적고, 앱의 동네 고르기 화면 아래에도 한 줄로 보인다. 지우면 안 된다.
#
# ## 쓰는 법
#
#   curl -o hangjeongdong.geojson \
#     https://raw.githubusercontent.com/vuski/admdongkor/master/ver20230101/HangJeongDong_ver20230101.geojson
#   python app/tool/build_regions.py hangjeongdong.geojson app/assets/regions/hangjeongdong.json
#
# ## 중심점을 어떻게 잡나
#
# 가장 큰 폴리곤 링의 꼭짓점 평균이다. 무게중심(centroid)이 아니라 평균인 이유는 이 값이
# **지도 첫 화면의 중심**으로만 쓰이기 때문이다 — 몇백 미터 차이가 뜻을 바꾸지 않는다.
# 섬이 딸린 동(예: 옹진군)에서 가장 큰 조각을 고르는 것이 본섬을 고르는 것과 같다.
import io
import json
import sys


def ring_center(ring):
    """링(꼭짓점 목록)의 평균 좌표와 대략적인 크기."""
    if not ring:
        return None, 0.0
    lngs = [p[0] for p in ring]
    lats = [p[1] for p in ring]
    span = (max(lngs) - min(lngs)) * (max(lats) - min(lats))
    return (sum(lngs) / len(lngs), sum(lats) / len(lats)), span


def feature_center(geometry):
    """가장 큰 링의 중심. MultiPolygon·Polygon 둘 다 받는다."""
    kind = geometry.get('type')
    rings = []
    if kind == 'Polygon':
        rings = geometry.get('coordinates', [])
    elif kind == 'MultiPolygon':
        for polygon in geometry.get('coordinates', []):
            rings.extend(polygon)
    best, best_span = None, -1.0
    for ring in rings:
        center, span = ring_center(ring)
        if center and span > best_span:
            best, best_span = center, span
    return best


def build(src_path, out_path):
    with io.open(src_path, encoding='utf-8') as f:
        data = json.load(f)

    sido = {}
    sigungu = {}
    dong = []

    for feature in data.get('features', []):
        props = feature.get('properties', {})
        code = props.get('adm_cd2') or props.get('adm_cd')
        name = props.get('adm_nm', '')
        sido_code = props.get('sido')
        sido_name = props.get('sidonm')
        sgg_code = props.get('sgg')
        sgg_name = props.get('sggnm')
        if not (code and sido_code and sgg_code):
            continue

        center = feature_center(feature.get('geometry', {}))
        if center is None:
            continue

        sido[sido_code] = sido_name
        sigungu[sgg_code] = (sido_code, sgg_name)
        # 동 이름만 남긴다 — "서울특별시 종로구 사직동" 에서 앞 둘은 위 표에 있다.
        short = name.replace(sido_name, '', 1).replace(sgg_name, '', 1).strip()
        dong.append({
            'c': code,
            'g': sgg_code,
            'n': short or name,
            # 소수점 다섯 자리면 약 1m 다. 지도 첫 화면에 그보다 정밀할 이유가 없고,
            # 자리를 줄이면 파일이 3분의 1 이 된다.
            'lat': round(center[1], 5),
            'lng': round(center[0], 5),
        })

    out = {
        'version': data.get('name', ''),
        'source': '통계청 SGIS 행정동 경계(공공누리 제1유형) · '
                  'https://github.com/vuski/admdongkor (CC BY 4.0)',
        'note': '이 파일은 경계 GeoJSON 에서 이름·코드·중심점만 뽑은 것이다. '
                'app/tool/build_regions.py 로 다시 만든다.',
        'sido': [{'c': c, 'n': n} for c, n in sorted(sido.items())],
        'sigungu': [{'c': c, 's': s, 'n': n} for c, (s, n) in sorted(sigungu.items())],
        'dong': sorted(dong, key=lambda d: d['c']),
    }

    with io.open(out_path, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(out, f, ensure_ascii=False, separators=(',', ':'))

    print('시도 %d · 시군구 %d · 행정동 %d' % (len(out['sido']), len(out['sigungu']), len(out['dong'])))
    print('→ %s' % out_path)


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print('usage: python build_regions.py <geojson> <out.json>')
        raise SystemExit(2)
    build(sys.argv[1], sys.argv[2])
