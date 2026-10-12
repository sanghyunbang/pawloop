package com.heattrip.heat_trip_backend.moderation;

import java.time.Instant;

/**
 * 누군가 다른 사람을 차단했다 — {@link Blocks#block} 이 저장 트랜잭션 안에서 발행한다.
 *
 * <h2>왜 알리나 — 애플 App Review Guideline 1.2</h2>
 * <p>1.2 는 차단 수단에 조건을 하나 더 단다 — <b>차단하면 개발자에게도 알려야 한다.</b> App Store
 * 심사가 그 조건으로 반려했다. 신고는 {@link ReportFiled} 로 이미 알리고 있었고, 차단은 행만 남기고
 * 아무에게도 말하지 않았다.
 *
 * <h2>왜 사건인가 — {@link ReportFiled} 와 같은 이유다</h2>
 * <p>이 모듈은 {@code allowedDependencies = {}} 라 슬랙을 직접 못 부른다. 그래서 "차단됐다" 고
 * 말하기만 하고, 듣는 쪽({@code observability.alert.BlockAlertListener})이 알린다. 듣는 쪽은
 * {@code @TransactionalEventListener(AFTER_COMMIT)} 로 받아야 한다 — 커밋 전에 받으면 롤백된
 * 차단의 알림이 나간다.
 *
 * <h2>새로 차단했을 때만 난다</h2>
 * <p>이미 차단해 둔 사람을 다시 차단하면 {@link Blocks#block} 이 아무것도 안 바꾸고
 * {@code false} 를 돌려준다. 그때는 발행하지 않는다 — 같은 사실을 두 번 알리면 운영자는 두 사건으로
 * 읽는다. 동시에 두 요청이 들어와 UNIQUE 에 걸린 쪽도 같다.
 *
 * <h2>무엇을 싣나 — id 셋과 시각 하나</h2>
 * <ul>
 *   <li><b>이름이 없다.</b> 이 모듈은 {@code users} 를 모르고, 알 필요도 없다 — 운영자는 id 로
 *       DB 를 연다. 차단당한 사람의 이름이 알림 채널에 떠야 할 이유도 없다.</li>
 *   <li><b>어디서 차단했는지가 없다.</b> 경로가 {@code POST /api/blocks} 하나이고 방 id 도 글 id 도
 *       없다 — 차단은 처음부터 사람 단위다. 커뮤니티에서 했든 채팅에서 했든 같은 사건이다.</li>
 * </ul>
 *
 * @param blockId       {@code user_block.id}. 운영자가 DB 를 열 때의 좌표다
 * @param blockerUserId 차단한 사람
 * @param blockedUserId 차단당한 사람
 * @param blockedAt     차단 시각(UTC). 표시할 때 KST 로 바꾼다
 */
public record UserBlocked(long blockId, long blockerUserId, long blockedUserId, Instant blockedAt) {
}
