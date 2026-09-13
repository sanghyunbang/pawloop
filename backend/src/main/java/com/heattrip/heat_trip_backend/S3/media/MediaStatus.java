package com.heattrip.heat_trip_backend.S3.media;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;

import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;

/**
 * 업로드 한 건의 상태 — 이슈 #429.
 *
 * <h2>둘뿐이다</h2>
 * <p>{@link #PENDING} 은 "자리는 잡았는데 파일이 아직 S3 에 없다" 이고 {@link #READY} 는
 * "S3 에 있고 서버가 크기·형식을 확인했다" 다. 영상은 앱이 S3 에 <b>직접</b> 올리므로 이 둘
 * 사이가 있다. 사진은 서버가 받아 놓는 순간 {@code READY} 다.
 *
 * <p>"붙었다" 는 상태가 아니다 — 그건 {@code ref_type}·{@code ref_id} 가 채워졌는가로 안다.
 * 여기에 또 두면 같은 사실이 두 곳에 산다({@code CrewFavorStatus} 와 같은 판단).
 *
 * <p>DB 에는 {@link #wire} 값이 들어간다 — {@code CrewFavorStatus.Codec} 과 같은 규약이다.
 * {@code @Enumerated(STRING)} 을 쓰면 상수 이름({@code READY})이 저장돼 CHECK 의 소문자와 갈린다.
 */
public enum MediaStatus {

    /** 자리만 있다. 글에 붙지 않는다. */
    PENDING("pending"),

    /** 파일이 S3 에 있고 확인됐다. */
    READY("ready");

    private final String wire;

    MediaStatus(String wire) {
        this.wire = wire;
    }

    @JsonValue
    public String wire() {
        return wire;
    }

    @JsonCreator
    public static MediaStatus of(String value) {
        for (MediaStatus status : values()) {
            if (status.wire.equals(value)) {
                return status;
            }
        }
        throw new IllegalArgumentException("미디어 상태는 pending · ready 중 하나여야 합니다.");
    }

    public boolean isReady() {
        return this == READY;
    }

    @Converter(autoApply = false)
    public static class Codec implements AttributeConverter<MediaStatus, String> {
        @Override
        public String convertToDatabaseColumn(MediaStatus attribute) {
            return attribute == null ? null : attribute.wire;
        }

        @Override
        public MediaStatus convertToEntityAttribute(String dbData) {
            return dbData == null ? null : of(dbData);
        }
    }
}
