package com.heattrip.heat_trip_backend.moderation.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;

import lombok.AccessLevel;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;

import org.hibernate.annotations.Check;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;

/**
 * 신고 한 건 — 이슈 #166. 결정의 근거는 {@code mysql/post-start/15_report.sql} 머리에 있다.
 *
 * <h2>사용자 id 로 FK 를 안 건다</h2>
 * <p>옛 {@code chat_report}(#281 로 지웠다)와 같은 모양이다. 이 모듈이 <b>아무 도메인도 안 부른다</b>는 것이
 * 설계의 불변식이고(package-info), FK 를 걸려면 {@code @ManyToOne User} 가 필요해 그것이
 * 깨진다.
 *
 * <p>그리고 신고 기록에는 값이 더 낫다. {@code SET NULL} 로 두면 탈퇴한 사람이 누구를
 * 신고했는지·누가 신고당했는지가 함께 사라져, 운영자가 "이 사람이 반복 신고당했다" 를 셀 수
 * 없게 된다. id 는 재사용되지 않으므로 값으로 남겨도 다른 사람을 가리키지 않는다.
 *
 * <h2>UNIQUE 가 없다</h2>
 * <p>같은 사람이 같은 것을 여러 번 신고할 수 있다. <b>글이 수정되기 때문이다</b> — #211 이
 * {@code PATCH} 를 열었다. 막으면 작성자가 신고 뒤 본문을 더 나쁜 것으로 고쳤을 때 재신고가
 * 안 되고, 운영자에게 남는 기록은 <b>고치기 전 본문</b>뿐이다. 도배는 레이트리밋이 막는다
 * ({@code report} 버킷 분당 10).
 *
 * <h2>시각은 UTC 다</h2>
 * <p>{@code LocalDateTime} 인데 담긴 값이 UTC 다 — {@code Walk}·{@code Post} 가 #40 에서 정한
 * 규약과 같다. 응답은 {@link #createdAtInstant()} 로 오프셋을 갖고 나간다(#209).
 */
@Entity
@Table(name = "report", indexes = {
        @Index(name = "idx_report_reported", columnList = "reported_user_id"),
        @Index(name = "idx_report_reporter", columnList = "reporter_user_id"),
})
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor(access = AccessLevel.PRIVATE)
@Builder
@Check(name = "chk_report_reason",
        constraints = "reason in ('spam','abuse','sexual','fraud','other')")
public class Report {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    // 무엇을 신고했나 — **좌표는 여기 없다.** report_snapshot 이 든다 (#254).
    //
    // ADR-0016 은 target_type 축을 부모에 두면 채팅 흡수가 INSERT ... SELECT 라고 적었는데,
    // 채팅 신고가 한 건에 메시지 셋까지라 부모 한 칸으로는 안 담겼다. 그 산정이 틀렸다.
    //
    // 부모는 "누가·누구를·왜·언제" 만 든다. "무엇을" 은 사본마다 붙는다.

    @Column(name = "reporter_user_id", nullable = false)
    private long reporterUserId;

    /** 신고당한 사람. 탈퇴한 사람의 글이면 {@code null} 이다. */
    @Column(name = "reported_user_id")
    private Long reportedUserId;

    @Column(name = "reason", nullable = false, length = 16)
    private String reason;

    /** 자유 서술. <b>넘치면 400 이 아니라 잘린다</b> — 채팅과 같다. */
    @Column(name = "memo", length = 500)
    private String memo;

    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    /** 저장된 값을 다시 시각으로 세운다. 응답이 오프셋을 갖게 하는 자리다(#209). */
    public Instant createdAtInstant() {
        return createdAt.toInstant(ZoneOffset.UTC);
    }
}
