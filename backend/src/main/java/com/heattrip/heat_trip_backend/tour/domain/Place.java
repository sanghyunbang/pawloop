package com.heattrip.heat_trip_backend.tour.domain;

import java.time.LocalDateTime;
import java.util.Map;

import com.heattrip.heat_trip_backend.curation.entity.EmotionWeightMapJsonConverter;
import com.heattrip.heat_trip_backend.tour.util.Sanitizers;

import jakarta.persistence.Column;
import jakarta.persistence.Convert;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Lob;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.validation.constraints.Size;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

@Entity
@Table(name = "places")
@Getter @Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder

public class Place {

    // 예시: 전화번호는 100자로 제한(스키마와 맞추기)
    public static final int TEL_MAX_LEN = 100;
    public static final int TITLE_MAX_LEN = 255;
    public static final int ADDR_MAX_LEN = 255;
    public static final int ZIPCODE_MAX_LEN = 20;
    
    @Id
    private Long contentid; // 불러온 XML의 contentid

    @Size(max = TITLE_MAX_LEN)
    @Column(length = TITLE_MAX_LEN)
    private String title;
    
    @Size(max = ADDR_MAX_LEN)
    @Column(length = ADDR_MAX_LEN)
    private String addr1;
    
    @Size(max = ADDR_MAX_LEN)
    @Column(length = ADDR_MAX_LEN)
    private String addr2;

    @Size(max = ZIPCODE_MAX_LEN)
    @Column(length = ZIPCODE_MAX_LEN)    
    private String zipcode;

    private Double mapx;
    private Double mapy;

    private String firstimage;
    private String firstimage2;

    private String cat1;
    private String cat2;
    private String cat3;

    private Integer areacode;
    private Integer sigungucode;
    private Integer lDongRegnCd; // 법정동 시도 코드
    private Integer lDongSignguCd; // 법정동 시군구 코드

    @Size(max = TEL_MAX_LEN)
    @Column(length = TEL_MAX_LEN)    
    private String tel;

    private String contenttypeid;

    @Lob
    @Column(name = "search_text", columnDefinition = "LONGTEXT")
    private String searchText;

    // private String createdtime;
    // private String modifiedtime;
    // 빠른 정렬/필터링 위해서 varchar -> LocalDateTime으로 타입 변경
    // DB도 직접 쿼리문으로 타입 변경하기
    // DTO도 변경
    private LocalDateTime createdtime;
    private LocalDateTime modifiedtime;
    
    private String mlevel;

    /**
     * 시드 감정 분포(감정→가중치). 공공데이터 + LLM 1회 배치로 생성. nullable.
     * 예) {"평온":0.4,"설렘":0.3}
     */
    @Lob
    @Convert(converter = EmotionWeightMapJsonConverter.class)
    @Column(name = "seed_emotion", columnDefinition = "json")
    private Map<String, Double> seedEmotion;

    /** UGC 감정 분포(감정→가중치). 사용자 다이어리 기분에서 집계. nullable. */
    @Lob
    @Convert(converter = EmotionWeightMapJsonConverter.class)
    @Column(name = "ugc_emotion", columnDefinition = "json")
    private Map<String, Double> ugcEmotion;

    /** UGC 데이터포인트 수. 기본값 0. 5 미만이면 seed_emotion만 노출(가드 로직은 본 티켓 범위 밖). */
    @Builder.Default
    @Column(name = "ugc_count", nullable = false)
    private int ugcCount = 0;

    @PrePersist
    @PreUpdate
    private void sanitizeAndTruncate() {
        this.tel = Sanitizers.cleanTel(this.tel, TEL_MAX_LEN);
        this.title = Sanitizers.truncate(this.title, TITLE_MAX_LEN);
        this.addr1 = Sanitizers.truncate(this.addr1, ADDR_MAX_LEN);
        this.addr2 = Sanitizers.truncate(this.addr2, ADDR_MAX_LEN);
        this.zipcode = Sanitizers.truncate(this.zipcode, ZIPCODE_MAX_LEN);
        this.searchText = buildBaseSearchText();
    }

    private String buildBaseSearchText() {
        return String.join(" ",
            safeToken(title),
            safeToken(cat1),
            safeToken(cat2),
            safeToken(cat3)
        ).trim();
    }

    private String safeToken(String value) {
        return value == null ? "" : value.trim();
    }
}
