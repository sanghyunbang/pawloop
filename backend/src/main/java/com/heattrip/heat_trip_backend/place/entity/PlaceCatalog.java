package com.heattrip.heat_trip_backend.place.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Lob;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

import org.hibernate.annotations.Check;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.LocalDateTime;

/**
 * 전국 반려동반 장소 <b>한 벌</b> — 이슈 #273.
 *
 * <h2>{@code place_cell} 과 무엇이 다른가</h2>
 * <p>{@link PlaceCell} 은 <b>좌표</b>를 0.02° 격자로 접은 키를 쓴다. 이 표에는 <b>키가 없다.</b>
 * <b>출처마다</b> 전국 한 벌이고 행이 하나다(#291 — {@code kto}·{@code localdata}·{@code durunubi}).
 * 그래서 <b>요청에 좌표도 지역도 실려 오지 않는다</b> —
 * A안 빌드(완전 온디바이스)가 쓰는 길이다.
 *
 * <p>앱은 이 한 벌을 받아 기기에 두고, 거리 정렬과 반경 필터를 <b>자기 좌표로 기기에서</b>
 * 한다. 서버는 "누가 지도를 열었다" 까지만 안다.
 *
 * <h2>한 벌이 그렇게 크지 않다 (실측 2026-09-04)</h2>
 * <p>전국이 <b>9,684곳</b>이고 {@link #payload} 로 2.83MB, gzip 으로 <b>0.44MB</b> 다.
 * 시군구 249개로 쪼개는 설계를 접은 이유가 이 숫자다 — 쪼개면 요청에 지역이 실리고
 * (행정구역이지만 0 은 아니다) 한 벌 데우는 콜이 10 에서 249 로 는다.
 *
 * <h2>{@link #id} 와 {@link #source} 가 고정인 이유</h2>
 * <p>출처당 행이 하나라는 것을 <b>DB 가 지키게</b> 한다 — {@code source} 가 UNIQUE 이고
 * CHECK 가 세 값만 허용한다. 관례로만 두면 두 인스턴스가 동시에 갱신할 때 행이 둘이 되고,
 * 그때 어느 것이 답인지 코드에 안 적혀 있다. #273 에서는 {@code CHECK (id = 1)} 로 행이
 * 하나였고, #291 이 출처별 행으로 넓혔다 — 번호는 {@link com.heattrip.heat_trip_backend.place.CatalogSource} 가 든다.
 *
 * <h2>{@link #payload} 를 파싱해서 서빙하지 않는다</h2>
 * <p>이 문자열이 <b>응답 본문 그대로</b>다. 꺼내서 객체로 만들었다가 다시 직렬화하면
 * 요청마다 2.83MB 를 두 번 훑는다. 저장할 때 한 번 만들고, 그 뒤로는 바이트를 옮기기만 한다.
 *
 * <h2>{@link #etag} 는 {@link #payload} 의 해시다</h2>
 * <p>{@code fetchedAt} 을 ETag 로 쓰면 <b>내용이 같아도</b> 갱신할 때마다 값이 바뀌어
 * 앱이 2.83MB 를 다시 받는다. 해시면 KTO 데이터가 안 바뀐 날은 304 로 끝난다.
 *
 * <p>행에 저장하는 이유: 재시작해도 같고, 인스턴스가 여럿이어도 같다.
 */
@Entity
@Table(name = "place_catalog",
        uniqueConstraints = @UniqueConstraint(name = "uk_place_catalog_source", columnNames = "source"))
@Check(name = "chk_place_catalog_source", constraints = "source in ('kto','localdata','durunubi')")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class PlaceCatalog {

    /** {@code CatalogSource.id()} — 출처마다 고정 번호다. 1 이 KTO 다. */
    @Id
    @Column(name = "id", nullable = false)
    private Integer id;

    /** {@code CatalogSource.wireValue()} — {@code kto}·{@code localdata}·{@code durunubi}. UNIQUE + CHECK. */
    @Column(name = "source", nullable = false, length = 16)
    private String source;

    /** 정규화된 {@code Place} 배열 JSON. <b>응답 본문 그대로다.</b> */
    @Lob
    @Column(name = "payload", nullable = false, columnDefinition = "LONGTEXT")
    private String payload;

    /** {@link #payload} 의 SHA-256 앞 32자(hex). 약한 ETag 가 아니라 내용 해시다. */
    @Column(name = "etag", nullable = false, length = 64)
    private String etag;

    /** 실제로 담긴 개수. */
    @Column(name = "item_count", nullable = false)
    private int itemCount;

    /**
     * 출처가 말한 전체 수 — 레이어는 못 담는 행(좌표 없음 · GPX 실패)을 뺀 뒤다.
     * {@link #itemCount} 보다 크면 <b>잘렸다</b>.
     */
    @Builder.Default
    @Column(name = "total_count", nullable = false)
    private int totalCount = 0;

    /** 마지막으로 성공한 시각. 담긴 값이 서비스 존의 벽시계다. */
    @Column(name = "fetched_at", nullable = false)
    private LocalDateTime fetchedAt;

    /** 마지막으로 실패한 시각. {@code null} 이면 실패한 적이 없다. */
    @Column(name = "failed_at")
    private LocalDateTime failedAt;

    /** 연속 실패 횟수. 백오프가 이 값을 본다. */
    @Builder.Default
    @Column(name = "fail_streak", nullable = false)
    private int failStreak = 0;
}
