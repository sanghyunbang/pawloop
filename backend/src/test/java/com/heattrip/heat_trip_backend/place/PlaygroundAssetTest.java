package com.heattrip.heat_trip_backend.place;

import java.util.List;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.place.dto.PlaceDto;
import com.heattrip.heat_trip_backend.place.layer.PlaygroundAsset;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 저장소에 넣어 둔 반려견 놀이터 자산 — 이슈 #346.
 *
 * <h2>여기서 재는 것</h2>
 * <p>이 자산은 <b>지자체 CSV 를 사람이 받아 합친 것</b>이라({@code build_playgrounds.py})
 * 파일마다 컬럼 이름이 다르고, 좌표를 안 주는 파일도 있다. 스크립트가 그런 파일을 건너뛰게
 * 돼 있지만, 잘못 합쳐 (0,0) 이 섞이면 <b>지도에 그려지기 전까지 아무도 모른다.</b>
 *
 * <h2>수가 적은 것은 지금 사실이다</h2>
 * <p>전국 표준데이터가 없어 고양시 6곳으로 시작한다. 그래서 "몇 곳 이상" 을 재지 않는다 —
 * 재면 다음에 파일 하나를 더 넣을 때까지 빨간불이 남고, 그건 지키는 것이 아니라 막는 것이다.
 * 대신 <b>비어 있지 않다</b>와 <b>값이 성립한다</b>를 잰다.
 *
 * <p>네트워크를 타지 않는다. 클래스패스의 파일만 읽는다(#21).
 */
class PlaygroundAssetTest {

    private final List<PlaceDto> playgrounds = new PlaygroundAsset(new ObjectMapper()).load();

    @Test
    @DisplayName("자산이 비어 있지 않다 — 비면 놀이터 칩이 어디서나 빈 화면이다")
    void assetIsNotEmpty() {
        assertThat(playgrounds)
                .as("""
                        data/playgrounds.json 이 없거나 깨졌다. \
                        backend/tools/build_playgrounds.py 로 다시 만든다.""")
                .isNotEmpty();
    }

    @Test
    @DisplayName("좌표가 한반도 안이다 — 컬럼을 잘못 짚으면 (0,0) 이 섞인다")
    void coordinatesAreInKorea() {
        assertThat(playgrounds).allSatisfy(p -> {
            assertThat(p.lat()).isBetween(33.0, 38.7);
            assertThat(p.lng()).isBetween(124.5, 132.0);
        });
    }

    @Test
    @DisplayName("놀이터로 나간다 — source 와 category 가 같은 값이다")
    void speaksThePlaygroundCategory() {
        assertThat(playgrounds).allSatisfy(p -> {
            assertThat(p.source()).isEqualTo(PlaceDto.SOURCE_PLAYGROUND);
            assertThat(p.category()).isEqualTo(PlaceDto.SOURCE_PLAYGROUND);
            assertThat(p.contentId()).startsWith("playground:");
            assertThat(p.title()).isNotBlank();
        });
    }

    @Test
    @DisplayName("id 가 겹치지 않는다 — 도 파일과 시 파일에 같은 곳이 있을 수 있다")
    void idsAreUnique() {
        assertThat(playgrounds.stream().map(PlaceDto::contentId).distinct().count())
                .isEqualTo(playgrounds.size());
    }

    @Test
    @DisplayName("계약이 아는 카테고리다 — 앱이 라벨을 못 찾으면 빈 칸이 된다")
    void categoryIsInTheContract() {
        assertThat(PlaceDto.LAYER_SOURCES).contains(PlaceDto.SOURCE_PLAYGROUND);
    }
    @Test
    @DisplayName("요약이 비어 있다 — 관리 부서 이름(\"농업기술센터 농산유통과\")을 카드에 적지 않는다")
    void doesNotShowTheManagingDepartment() {
        // 데이터는 맞지만 사용자가 읽을 문장이 아니다. 반려견 놀이터 카드에 농업 부서 이름이
        // 뜨면 "무슨 농업 공사냐" 가 된다 — 실제로 그렇게 신고가 왔다.
        assertThat(playgrounds)
                .allSatisfy(p -> assertThat(p.summary()).isNull());
    }

    @Test
    @DisplayName("전화번호는 그대로 있다 — 문의할 길까지 없애지는 않는다")
    void keepsTheTelephone() {
        assertThat(playgrounds).anySatisfy(p -> assertThat(p.tel()).isNotBlank());
    }
}
