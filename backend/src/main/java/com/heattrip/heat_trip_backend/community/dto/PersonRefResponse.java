package com.heattrip.heat_trip_backend.community.dto;

import com.heattrip.heat_trip_backend.user.entity.User;

/**
 * 사람 하나를 가리키는 공통 모양 — 계약의 {@code PersonRef}(ADR-0017 규약 5).
 *
 * <h2>탈퇴한 사람은 {@code userId = 0} · {@code nickname = "알 수 없음"}</h2>
 * <p>커뮤니티에서 {@code user} 가 {@code null} 인 행은 <b>탈퇴한 사람이 쓴 것</b>이다 —
 * {@code users} FK 가 {@code ON DELETE SET NULL} 이라 DB 가 그렇게 눕힌다(#222).
 *
 * <p>그래서 <b>{@code WithdrawnUsers} 를 부르지 않는다.</b> {@code social} 은 {@code user_id} 를
 * FK 없는 스칼라로 들어서 "이 id 가 아직 있는가" 를 따로 물어야 하지만, 여기는 진짜 FK 라
 * <b>{@code null} 인 것이 곧 탈퇴</b>다. 쿼리 한 번이 줄고, 그 사실을 여기 적어 두지 않으면
 * 다음 사람이 {@code social} 을 보고 그 조회를 되살린다.
 *
 * <p>커뮤니티에는 익명 글이 없다 — 쓰기 넷이 전부 인증 필수라 {@code null} 을 "처음부터 익명"
 * 으로 읽을 여지가 없다. ({@code WithdrawnUsers.among} 의 javadoc 이 그 구분을 부르는 쪽이
 * 유지하라고 적어 둔 자리다.)
 *
 * <h2>{@code nickname} 은 조회 시점의 현재 값이다</h2>
 * <p>{@code post.handle}·{@code comment.handle} 에 작성 시점 스냅샷이 저장돼 있지만
 * <b>응답에는 싣지 않는다.</b> 저장은 스냅샷, 표시는 현재값 — 두 규칙이 한 화면에서 만나면
 * 같은 사람의 글 둘이 다른 이름으로 보인다(ADR-0017 규약 5).
 */
public record PersonRefResponse(long userId, String nickname) {

    /** 탈퇴한 계정. 계약이 못 박은 값이다. */
    private static final PersonRefResponse WITHDRAWN = new PersonRefResponse(0L, "알 수 없음");

    /** @param user {@code null} 이면 탈퇴한 사람이다 — 위 javadoc 참조 */
    public static PersonRefResponse of(User user) {
        if (user == null) {
            return WITHDRAWN;
        }
        // 닉네임이 비어 있는 계정이 있다 — 소셜 공급자가 안 준 경우다. 그때는 이름으로,
        // 그것도 없으면 탈퇴와 같은 문구로 떨어뜨린다. 빈 문자열을 그대로 실으면 화면에
        // 이름 없는 줄이 생기고, 그건 "누가 썼는지 모른다" 와 같은 상태다.
        String shown = firstNonBlank(user.getNickname(), user.getName());
        return shown == null
                ? new PersonRefResponse(user.getId(), WITHDRAWN.nickname())
                : new PersonRefResponse(user.getId(), shown);
    }

    private static String firstNonBlank(String a, String b) {
        if (a != null && !a.isBlank()) {
            return a;
        }
        return b != null && !b.isBlank() ? b : null;
    }
}
