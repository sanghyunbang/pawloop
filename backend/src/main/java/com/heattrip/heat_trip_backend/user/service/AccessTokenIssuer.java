package com.heattrip.heat_trip_backend.user.service;

/**
 * 액세스 토큰을 발급하는 것. <b>{@code user} 가 정의하고 밖이 구현한다.</b> (#107)
 *
 * <h2>왜 인터페이스인가</h2>
 * <p>{@code user} 는 세션 토큰을 발급해야 하는데, 그 구현({@code OAuth.jwt.JWTProvider})을
 * 직접 부르면 {@code user -> OAuth} 화살표가 생긴다. 그런데 {@code OAuth} 는 이미
 * {@code user} 를 부른다 — 외부 신원을 우리 사용자로 바꾸는 번역 층이라 그게 자연스럽다.
 * 양쪽이 서로를 알면 순환이고, 순환은 {@code type = OPEN} 으로도 {@code @NamedInterface} 로도
 * 안 꺼진다. 코드를 바꿔야만 없어진다.
 *
 * <p>그래서 방향을 하나로 정했다 — <b>{@code OAuth -> user} 를 남기고 {@code user -> OAuth} 를
 * 끊는다.</b> {@code user} 는 "토큰을 발급해 달라" 는 요구만 적고, 어떻게 만드는지는 모른다.
 *
 * <h2>어댑터를 만들지 않는다</h2>
 * <p>메서드 시그니처를 {@code JWTProvider} 의 것과 <b>글자 그대로</b> 맞췄다. 그래서 그 클래스가
 * {@code implements} 한 마디만 붙이면 되고 위임 클래스가 필요 없다. 위임 한 줄짜리 어댑터는
 * 아무 테스트도 겨누지 않아서 커버리지 하한(0.80, {@code OAuth/**} + {@code user/**} 한 묶음)을
 * 조용히 갉아먹는다.
 *
 * <h2>구현이 하나라고 인터페이스가 무의미한 것은 아니다</h2>
 * <p>여기서 인터페이스가 하는 일은 다형성이 아니라 <b>방향 고정</b>이다. 구현이 앞으로도 하나뿐일
 * 가능성이 높고, 그래도 된다.
 */
public interface AccessTokenIssuer {

    /**
     * 액세스 토큰 문자열. {@code role} 은 DB 의 role 컬럼 값이다 — 예전에 여기서
     * {@code "ROLE_USER"} 를 하드코딩했다가 이슈 #7 이 걷어냈다.
     */
    String createAccessToken(Long userId, String role);

    /** 발급한 토큰이 몇 초 뒤에 만료되는가. 로그인 응답의 {@code expiresIn} 이 이 값이다. */
    long getExpiresInSeconds();
}
