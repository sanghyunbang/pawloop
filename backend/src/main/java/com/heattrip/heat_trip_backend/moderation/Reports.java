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
     * 신고가 통째로 사라지는데, 잘린 메모로도 운영자의 판단에는 충분하다.
     *
     * <h2>좌표는 사본마다 붙는다 — 이슈 #254</h2>
     * <p>예전에는 이 메서드가 {@code ReportTarget} 을 따로 받아 부모에 넣었다. 채팅 신고가
     * 한 건에 메시지 셋까지라 그 모양으로는 안 담겨서, 좌표를 {@link ReportSnapshotInput}
     * 으로 내렸다. 여기서는 <b>대상 줄들이 서로 앞뒤가 맞는지</b>만 본다.
     *
     * @param reporterUserId 신고한 사람
     * @param reportedUserId 신고당한 사람. 탈퇴한 사람의 글이면 {@code null}
     * @param reason         분류
     * @param memo           자유 서술. {@code null} 이거나 공백뿐이면 안 저장한다
     * @param inputs         신고 시점 사본. 규칙은 {@link #requireCoherentTargets}
     */
    @Transactional
    public ReportReceipt file(long reporterUserId,
                              Long reportedUserId,
                              ReportReason reason,
                              String memo,
                              List<ReportSnapshotInput> inputs) {

        requireCoherentTargets(inputs);

        Report saved = reports.save(Report.builder()
                .reporterUserId(reporterUserId)
                .reportedUserId(reportedUserId)
                .reason(reason.wireValue())
                .memo(trimmedMemo(memo))
                .createdAt(ModerationTime.nowUtc(clock))
                .build());

        List<ReportSnapshot> rows = new ArrayList<>(inputs.size());
        for (ReportSnapshotInput input : inputs) {
            rows.add(ReportSnapshot.builder()
                    .report(saved)
                    .role(input.role().wireValue())
                    .targetType(input.target().type().wireValue())
                    .targetId(input.target().id())
                    .targetOrdinal(input.targetOrdinal())
                    .authorUserId(input.authorUserId())
                    .authorName(input.authorName())
                    .title(input.title())
                    .body(input.body())
                    .contentType(input.contentType())
                    .occurredAt(LocalDateTime.ofInstant(input.occurredAt(), ZoneOffset.UTC))
                    .build());
        }
        snapshots.saveAll(rows);

        return new ReportReceipt(saved.getId(), saved.createdAtInstant());
    }

    /**
     * 대상 줄들이 서로 앞뒤가 맞는가 — 이슈 #254.
     *
     * <p>좌표가 부모에 있을 때는 "정확히 하나" 가 <b>구조로</b> 보장됐다. 자식으로 내리면서
     * 그 보장이 사라졌으므로 여기서 대신 든다. 넷을 본다.
     *
     * <ol>
     *   <li><b>대상이 하나는 있다.</b> 없으면 원본이 지워진 뒤 아무것도 못 읽는다.</li>
     *   <li><b>종류가 하나다.</b> 글과 메시지를 한 건에 섞으면 운영자가 무엇을 판단하는지
     *       모르고, 신고당한 사람도 하나로 못 정해진다.</li>
     *   <li><b>그 종류의 상한을 안 넘는다.</b> {@link ReportTarget.Type#maxTargets()} 이
     *       답한다 — 커뮤니티 1, 채팅 3. {@code 0} 인 종류({@code CHAT_ROOM})는 대상이
     *       될 수 없다.</li>
     *   <li><b>같은 좌표가 두 번 오지 않는다.</b> 오면 앱이 같은 것을 두 번 실어
     *       상한을 우회한 것이다.</li>
     * </ol>
     *
     * <p>전부 <b>프로그래밍 오류</b>다 — 사용자 입력으로는 여기 올 수 없다. 부르는 쪽이
     * 이미 걸렀고, 못 걸렀으면 그쪽 버그다.
     */
    private static void requireCoherentTargets(List<ReportSnapshotInput> inputs) {
        List<ReportSnapshotInput> targets = inputs.stream()
                .filter(input -> input.role() == ReportSnapshotInput.Role.TARGET)
                .toList();

        if (targets.isEmpty()) {
            throw new IllegalStateException("신고 사본에 대상이 하나도 없습니다.");
        }

        ReportTarget.Type type = targets.get(0).target().type();
        boolean mixed = targets.stream().anyMatch(input -> input.target().type() != type);
        if (mixed) {
            throw new IllegalStateException(
                    "한 신고의 대상은 종류가 하나여야 합니다. 지금 "
                            + targets.stream().map(input -> input.target().type().wireValue())
                                    .distinct().toList() + " 가 섞여 있습니다.");
        }

        if (targets.size() > type.maxTargets()) {
            throw new IllegalStateException(
                    "%s 는 신고 한 건에 %d개까지입니다. 지금 %d개입니다."
                            .formatted(type.wireValue(), type.maxTargets(), targets.size()));
        }

        long distinct = targets.stream().map(input -> input.target().id()).distinct().count();
        if (distinct != targets.size()) {
            throw new IllegalStateException(
                    "같은 대상이 두 번 실렸습니다. 상한이 그만큼 우회됩니다.");
        }
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
