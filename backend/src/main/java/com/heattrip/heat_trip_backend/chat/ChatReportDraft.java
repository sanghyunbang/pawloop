package com.heattrip.heat_trip_backend.chat;

import java.time.Instant;
import java.util.List;

/**
 * 접수 직전의 채팅 신고 — {@code chat} 이 판정을 마치고 <b>값으로</b> 내보내는 모양. 이슈 #254.
 *
 * <h2>왜 chat 이 저장을 안 하나</h2>
 * <p>신고 표가 둘이었다. {@code chat_report} 와 {@code report} 가 같은 것을 다르게 들고
 * 있었고, 운영자가 두 군데를 봐야 했다(#254).
 *
 * <p>합치는데 {@code chat} 이 {@code moderation} 을 직접 못 부른다 — 둘 다
 * {@code allowedDependencies = &#123;&#125;} 이고, {@code ChatBoundaryArchitectureTest} §B 가
 * chat 소스에 다른 도메인 이름이 나오는 것을 import 든 완전수식명이든 막는다.
 *
 * <p>그래서 <b>판정은 chat 에 남고 저장만 나간다.</b> 멤버십 403, 분류 검증, 중복 seq 합치기,
 * 개수 상한, 단일 발신자, 자기 신고 거절 — 전부 {@code ChatReportService} 안에 그대로 있다.
 * {@code ChatErrorCode} 여섯이 밖으로 새지 않는 것이 요점이다.
 *
 * <h2>왜 한 트랜잭션이 아니어도 되나</h2>
 * <p>이 record 는 <b>본문을 값으로 들고 있다.</b> 읽은 뒤 저장하기 전에 원본이 바뀌어도
 * 저장되는 것은 읽은 그 순간의 사본이다 — 그게 사본이 있는 이유다. 그래서 부르는 쪽
 * ({@code chatweb})에 트랜잭션이 필요 없고, 실제로 그 패키지는
 * <b>"판정도 트랜잭션도 여기 없다"</b> 를 package-info 에 못 박아 두었다.
 *
 * @param roomId         신고가 일어난 방. 이 값이 없으면 {@link Target#roomSeq()} 가 어느 방의
 *                       번호인지 모른다 — 방이 지워져도 남아야 하는 좌표다
 * @param reportedUserId 신고당한 사람. 채팅은 <b>단일 발신자를 강제</b>하므로 하나다
 * @param reason         분류. 이미 검증된 값이다
 * @param memo           덧붙이는 말. 이미 잘린 값이고, 없으면 {@code null}
 * @param targets        고른 메시지들. 1개 이상이고 {@code ChatLimits} 의 상한 이하다
 */
public record ChatReportDraft(
        long roomId,
        long reportedUserId,
        String reason,
        String memo,
        List<Target> targets) {

    /**
     * 고른 메시지 하나의 사본.
     *
     * @param messageId   {@code chat_message.id}. 원본이 살아 있는 동안 맥락을 열어 볼 실마리다
     * @param roomSeq     방 안 번호. <b>맥락 범위를 이 값으로 다시 센다</b> —
     *                    {@code context_from/to_seq} 는 이 값들과 반경 상수에서 완전히
     *                    유도되는 파생값이라 따로 안 담는다
     * @param senderUserId 보낸 사람
     * @param senderName  보낸 시점 표시 이름
     * @param body        보낸 시점 본문
     * @param contentType 본문의 종류. 이미지 신고와 글 신고가 구분되어야 한다
     * @param sentAt      보낸 시각
     */
    public record Target(
            long messageId,
            long roomSeq,
            long senderUserId,
            String senderName,
            String body,
            String contentType,
            Instant sentAt) {
    }
}
