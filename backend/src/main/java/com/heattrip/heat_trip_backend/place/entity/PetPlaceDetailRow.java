package com.heattrip.heat_trip_backend.place.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Lob;
import jakarta.persistence.Table;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.LocalDateTime;

/**
 * 장소 상세 캐시 — 이슈 #40.
 *
 * <h2>시각이 소스별로 둘이다</h2>
 * <p>{@link #commonFetchedAt} 은 {@code detailCommon2}(개요), {@link #petFetchedAt} 은
 * {@code detailPetTour2}(반려동반 정보)의 시각이다.
 *
 * <p>하나로 합치면 <b>부분 성공이 완전 성공과 구분되지 않는다</b> — "개요는 받았는데
 * 반려동반 정보만 타임아웃" 인 상태가 30일 동안 눌어붙고, 사용자에게는 "이 장소는 동반
 * 정보가 없다" 로 보인다. 둘로 나누면 다음 요청이 빠진 쪽만 다시 부른다.
 *
 * <h2>{@link #notFoundAt} 이 음수 캐시다</h2>
 * <p>KTO 가 모르는 {@code contentId} 를 기억해 둔다. 이게 없으면 <b>무작위 id 를 던지는
 * 것만으로 상세 예산을 태울 수 있다</b> — 상세 1건이 2콜이므로 75번이면 하루치가 사라진다.
 *
 * <h2>행이 있다는 것 자체가 허용목록이다</h2>
 * <p>셀 스냅샷을 저장할 때 그 안의 모든 {@code contentId} 로 <b>빈 행</b>을 함께 만든다.
 * 상세 요청은 이 표에 행이 있어야 아웃바운드로 나갈 수 있다. 즉 "우리가 한 번이라도 목록에
 * 실어 보낸 장소" 만 상세를 받을 수 있다.
 */
@Entity
@Table(name = "pet_place_detail")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class PetPlaceDetailRow {

    /** KTO 가 준 불투명 문자열. <b>우리 표의 키가 아니라</b> FK 를 걸지 않는다. */
    @Id
    @Column(name = "content_id", nullable = false, length = 64)
    private String contentId;

    /**
     * 목록에 실어 보낼 때 함께 적어 두는 기본 필드들.
     *
     * <p>상세 응답이 계약상 {@code allOf: [Place, ...]} 라 제목·좌표·주소가 함께 나가야
     * 하는데, 셀 스냅샷 JSON 을 뒤져 찾으면 표 전체를 훑게 된다. 여기 적어 두는 편이 싸다.
     */
    @Column(name = "title", length = 255)
    private String title;

    @Column(name = "addr", length = 255)
    private String addr;

    @Column(name = "tel", length = 64)
    private String tel;

    @Column(name = "image", length = 512)
    private String image;

    @Column(name = "lat")
    private Double lat;

    @Column(name = "lng")
    private Double lng;

    @Column(name = "content_type_id", length = 16)
    private String contentTypeId;

    @Lob
    @Column(name = "overview", columnDefinition = "LONGTEXT")
    private String overview;

    /** 동반 가능 반려동물. KTO 가 자유 텍스트로 준다. */
    @Column(name = "acmpy_psbl_cpam", columnDefinition = "TEXT")
    private String acmpyPsblCpam;

    /** 동반 시 필요사항. */
    @Column(name = "acmpy_need_mtr", columnDefinition = "TEXT")
    private String acmpyNeedMtr;

    /** 기타 유의사항. */
    @Column(name = "etc_acmpy_info", columnDefinition = "TEXT")
    private String etcAcmpyInfo;

    /** {@code detailCommon2} 를 마지막으로 성공한 시각. {@code null} 이면 아직 안 받았다. */
    @Column(name = "common_fetched_at")
    private LocalDateTime commonFetchedAt;

    /** {@code detailPetTour2} 를 마지막으로 성공한 시각. */
    @Column(name = "pet_fetched_at")
    private LocalDateTime petFetchedAt;

    /** KTO 가 모른다고 답한 시각. 음수 캐시다. */
    @Column(name = "not_found_at")
    private LocalDateTime notFoundAt;
}
