package com.heattrip.heat_trip_backend.place.service;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/** 한 벌들을 파싱 없이 잇는다 — 이슈 #291. */
class CatalogPayloadsTest {

    @Test
    @DisplayName("배열 셋을 하나로 잇는다 — 대괄호를 벗기고 콤마로")
    void concatenatesArrays() {
        String joined = CatalogPayloads.concat(List.of("[{\"a\":1}]", " [{\"b\":2},{\"c\":3}] ", "[]"));
        assertThat(joined).isEqualTo("[{\"a\":1},{\"b\":2},{\"c\":3}]");
    }

    @Test
    @DisplayName("전부 비면 [] 다")
    void allEmptyIsEmpty() {
        assertThat(CatalogPayloads.concat(List.of("[]", "[]"))).isEqualTo("[]");
    }

    @Test
    @DisplayName("배열이 아닌 것을 이으려 하면 던진다 — 조용히 깨진 본문을 내보내지 않는다")
    void refusesNonArrays() {
        assertThatThrownBy(() -> CatalogPayloads.concat(List.of("{\"a\":1}")))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    @DisplayName("합친 ETag 는 결정적이고, 한 벌이 바뀌면 바뀐다")
    void combinedEtagTracksEveryPart() {
        String a = CatalogPayloads.combinedEtag(List.of("aaa", "bbb"));
        assertThat(a).hasSize(32).isEqualTo(CatalogPayloads.combinedEtag(List.of("aaa", "bbb")));
        assertThat(CatalogPayloads.combinedEtag(List.of("aaa", "ccc"))).isNotEqualTo(a);
        assertThat(CatalogPayloads.combinedEtag(List.of("bbb", "aaa"))).as("순서도 내용이다").isNotEqualTo(a);
    }
}
