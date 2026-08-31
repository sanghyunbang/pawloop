package com.heattrip.heat_trip_backend.security;

import jakarta.servlet.http.HttpServletRequest;

/**
 * 요청을 보낸 쪽의 IP. <b>신뢰 프록시 판정이 걸린 자리다.</b> (이슈 #14 · #80 에서 꺼냄)
 *
 * <p><b>복사하면 안 되는 이유.</b> 헤더는 요청을 보낸 쪽이 적는 문자열이라 그 자체로는 아무것도
 * 증명하지 않는다. 증명할 수 있는 값은 {@code request.getRemoteAddr()} 하나뿐이므로, 그 주소가
 * 신뢰 목록 안에 있을 때만 헤더를 해석한다. 이 판정이 두 벌이 되면 한쪽만 고치는 날이 오고,
 * 그 순간 카운터 열쇠를 공격자가 정할 수 있게 된다 — #14 에서 실제로 있었던 일이다
 * (위조 헤더 1000건에 429 가 0건이었다).
 */
class ClientIpResolver {

    private final RateLimitProperties rateLimitProperties;

    /** {@link #trustedProxies()} 가 채운다. 기동 뒤 바뀌지 않는 값이라 한 번만 파싱한다. */
    private volatile TrustedProxies trustedProxies;

    ClientIpResolver(RateLimitProperties rateLimitProperties) {
        this.rateLimitProperties = rateLimitProperties;
    }

    /**
     * 카운터의 열쇠가 될 클라이언트 주소. <b>신뢰 경계를 명시한다.</b> (이슈 #14)
     *
     * <h2>무엇이 문제였나</h2>
     * 예전 구현은 {@code X-Forwarded-For} 의 <b>첫 원소</b>를 무조건 취했다. 그런데 이
     * 저장소의 nginx 템플릿({@code nginx-production-template.conf:34},
     * {@code nginx-rate-limit-example.conf:27})은 {@code $proxy_add_x_forwarded_for} 라서
     * <b>클라이언트가 보낸 값 뒤에</b> 실제 IP 를 덧붙인다. 즉 첫 원소는 배포된 환경에서도
     * 공격자가 정하는 문자열이었고, 요청마다 다른 값을 적으면 카운터가 갈라져 한도가
     * 통째로 사라졌다 — 한도 5 에 1000 요청, 429 <b>0건</b>.
     *
     * <h2>두 개의 벽</h2>
     * <ol>
     *   <li><b>연결 반대편이 신뢰 프록시가 아니면 헤더를 아예 읽지 않는다.</b> 헤더가 의미를
     *       갖는 조건은 "우리가 통제하는 프록시가 붙였다" 하나뿐이고, 그것을 확인할 수 있는
     *       값은 {@code getRemoteAddr()} 뿐이다. 프록시 없이 노출된 배포에서는 헤더가
     *       그냥 무시된다 — 위조가 통하지 않는다.</li>
     *   <li><b>목록형 헤더는 마지막 원소를 취한다.</b> 신뢰 프록시가 1단일 때 그 자리가
     *       프록시가 실제로 본 주소다. 앞쪽은 전부 클라이언트가 적은 값이다.
     *       ({@code X-Real-IP} 는 단일 값이라 마지막 = 전체다.)</li>
     * </ol>
     *
     * <p>둘 중 하나만 두면 부족하다. 1번만 두면 신뢰 프록시 뒤에서 첫 원소 위조가 그대로
     * 살아 있고, 2번만 두면 프록시 없는 배포에서 아무나 헤더를 붙일 수 있다.
     */
    String resolve(HttpServletRequest request) {
        String remoteAddr = request.getRemoteAddr();
        String connectionPeer = (remoteAddr == null || remoteAddr.isBlank()) ? "unknown" : remoteAddr;

        if (!trustedProxies().contains(connectionPeer)) {
            return connectionPeer;
        }

        String headerName = rateLimitProperties.getIpHeader();
        String forwarded = headerName == null ? null : request.getHeader(headerName);
        if (forwarded == null || forwarded.isBlank()) {
            return connectionPeer;
        }

        String[] hops = forwarded.split(",");
        String nearest = hops[hops.length - 1].trim();
        return nearest.isEmpty() ? connectionPeer : nearest;
    }

    /**
     * 신뢰 프록시 목록은 기동 뒤 바뀌지 않는다. 요청마다 CIDR 을 다시 파싱하지 않도록
     * 한 번만 만들어 둔다.
     */
    private TrustedProxies trustedProxies() {
        TrustedProxies cached = this.trustedProxies;
        if (cached == null) {
            cached = TrustedProxies.parse(rateLimitProperties.getTrustedProxies());
            this.trustedProxies = cached;
        }
        return cached;
    }
}
