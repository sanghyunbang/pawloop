package com.heattrip.heat_trip_backend.moderation;

import com.heattrip.heat_trip_backend.moderation.entity.Report;
import com.heattrip.heat_trip_backend.moderation.entity.ReportSnapshot;
import com.heattrip.heat_trip_backend.moderation.repository.ReportRepository;
import com.heattrip.heat_trip_backend.moderation.repository.ReportSnapshotRepository;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.List;

/**
 * 신고 접수 — 이 모듈의 공개 표면이다. 이슈 #166.
 *
 * <h2>시그니처에 {@code entity.*} 가 없다</h2>
 * <p>주고받는 것은 전부 이 패키지 <b>바로 아래</b> 타입이다 —
 * {@link ReportTarget}·{@link ReportReason}·{@link ReportSnapshotInput}·{@link ReportReceipt}.
 * Spring Modulith 는 모듈 패키지 바로 아래 타입만 공개 표면으로 보고, 하위 패키지를 부르는
 * 것 자체가 위반이라 기준선({@code BASELINE_VIOLATIONS})이 움직인다(📌 #95 §4).
 *
 * <h2>이 모듈은 아무 도메인도 안 부른다</h2>
 * <p>글이 무엇이고 누가 썼는지는 {@code community} 가 아는 것이라 <b>값으로 받는다.</b>
 * 그래서 여기서는 대상이 실재하는지도, 신고자가 그것을 볼 수 있는지도 확인하지 않는다 —
 * 그 판정은 부르는 쪽이 이미 하고 온다.
 *
 * <h2>중복을 막지 않는다</h2>
 * <p>같은 사람이 같은 것을 여러 번 신고할 수 있다. <b>글이 수정되기 때문이다</b>(#211).
 * 막으면 작성자가 신고 뒤 본문을 더 나쁜 것으로 고쳤을 때 재신고가 안 되고, 운영자에게
 * 남는 기록은 고치기 전 본문뿐이다. 도배는 레이트리밋이 막는다.
 */
@Service
@Transactional(readOnly = true)
public class Reports {

    /** 자유 서술의 최대 길이. 넘치면 <b>거절이 아니라 자른다</b> — 채팅과 같다. */
    public static final int MAX_MEMO_LENGTH = 500;

    private final ReportRepository reports;
    private final ReportSnapshotRepository snapshots;
    private final Clock clock;

    public Reports(ReportRepository reports, ReportSnapshotRepository snapshots, Clock clock) {
        this.reports = reports;
        this.snapshots = snapshots;
        this.clock = clock;
    }

    /**
     * 신고를 접수한다.
     *
     * <p>메모가 {@value #MAX_MEMO_LENGTH} 자를 넘으면 <b>자른다.</b> 400 을 주면 사용자가 쓴
     * 신고가 통째로 사라지는데, 잘린 메모로도 운영자의 판단에는 충분하다 — 채팅 신고가 같은
     * 판단을 이미 했다.
     *
     * @param target         무엇을 신고하나
     * @param reporterUserId 신고한 사람
     * @param reportedUserId 신고당한 사람. 탈퇴한 사람의 글이면 {@code null}
     * @param reason         분류
     * @param memo           자유 서술. {@code null} 이거나 공백뿐이면 안 저장한다
     * @param inputs         신고 시점 사본. <b>{@code TARGET} 이 정확히 하나</b> 있어야 하고,
     *                       댓글 신고라면 부모 글이 {@code CONTEXT} 로 함께 온다
     */
    @Transactional
    public ReportReceipt file(ReportTarget target,
                              long reporterUserId,
                              Long reportedUserId,
                              ReportReason reason,
                              String memo,
                              List<ReportSnapshotInput> inputs) {

        long targets = inputs.stream()
                .filter(input -> input.role() == ReportSnapshotInput.Role.TARGET)
                .count();
        if (targets != 1) {
            // 프로그래밍 오류다 — 사용자 입력으로는 여기 올 수 없다. 사본이 없으면 원본이
            // 지워진 뒤 아무것도 못 읽고, 둘이면 운영자가 무엇을 볼지 모른다.
            throw new IllegalStateException(
                    "신고 사본에는 대상이 정확히 하나 있어야 합니다. 지금 " + targets + "개입니다.");
        }

        Report saved = reports.save(Report.builder()
                .targetType(target.type().wireValue())
                .targetId(target.id())
                .reporterUserId(reporterUserId)
                .reportedUserId(reportedUserId)
                .reason(reason.wireValue())
                .memo(trimmedMemo(memo))
                .createdAt(nowUtc())
                .build());

        List<ReportSnapshot> rows = new ArrayList<>(inputs.size());
        for (ReportSnapshotInput input : inputs) {
            rows.add(ReportSnapshot.builder()
                    .report(saved)
                    .role(input.role().wireValue())
                    .authorUserId(input.authorUserId())
                    .authorName(input.authorName())
                    .title(input.title())
                    .body(input.body() == null ? "" : input.body())
                    .occurredAt(LocalDateTime.ofInstant(input.occurredAt(), ZoneOffset.UTC))
                    .build());
        }
        snapshots.saveAll(rows);

        return new ReportReceipt(saved.getId(), saved.createdAtInstant());
    }

    /**
     * 지금을 UTC 로. <b>마이크로초까지만</b> 자른다.
     *
     * <p>컬럼이 {@code DATETIME(6)} 이라 나노초는 DB 에서 잘린다. 안 자르고 넣으면 응답으로
     * 돌려준 시각과 저장된 시각이 달라지고, 그 차이가 테스트에서만 보인다.
     *
     * <p>담긴 값이 UTC 인 것은 {@code Walk}·{@code Post} 가 #40 에서 정한 규약이다.
     */
    private LocalDateTime nowUtc() {
        return LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC)
                .truncatedTo(ChronoUnit.MICROS);
    }

    /** 공백뿐이면 없는 것으로 본다. 넘치면 자른다. */
    private static String trimmedMemo(String memo) {
        if (memo == null) {
            return null;
        }
        String stripped = memo.strip();
        if (stripped.isEmpty()) {
            return null;
        }
        return stripped.length() <= MAX_MEMO_LENGTH
                ? stripped
                : stripped.substring(0, MAX_MEMO_LENGTH);
    }
}
