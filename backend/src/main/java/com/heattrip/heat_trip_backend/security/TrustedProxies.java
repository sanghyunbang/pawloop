package com.heattrip.heat_trip_backend.security;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.net.InetAddress;
import java.net.UnknownHostException;
import java.util.ArrayList;
import java.util.List;

/**
 * "이 TCP 연결의 반대편을 프록시로 믿어도 되는가" 하나만 답한다. (이슈 #14)
 *
 * <h2>왜 필요한가</h2>
 * {@code X-Forwarded-For}·{@code X-Real-IP} 는 <b>요청을 보낸 쪽이 적는 문자열</b>이다.
 * 그 값을 그대로 rate limit 카운터의 열쇠로 쓰면, 공격자가 요청마다 다른 값을 적어
 * 카운터를 무한히 갈라 놓을 수 있다 — 한도가 실질적으로 사라진다.
 *
 * <p>헤더가 <b>의미를 갖는 유일한 조건</b>은 "그 헤더를 우리가 통제하는 프록시가 붙였다"는
 * 것이다. 그리고 그것을 확인할 수 있는 값은 헤더가 아니라 {@code request.getRemoteAddr()}
 * — TCP 연결의 반대편 주소 — 하나뿐이다. 이 클래스가 그 판정만 맡는다.
 *
 * <h2>왜 CIDR 인가</h2>
 * 배포 형태가 셋이다. nginx 가 같은 호스트에 있으면 {@code 127.0.0.1}, 도커 브리지 너머면
 * {@code 172.17.0.1}, 사설망의 다른 호스트면 {@code 10.x}·{@code 192.168.x} 다. 문자열
 * 목록으로는 세 번째를 적을 수 없다.
 *
 * <p>목록에 <b>공인 대역을 넣지 말 것.</b> 넣는 순간 그 대역의 아무나 헤더로 자기 IP 를
 * 정할 수 있게 되고, 이 클래스가 있는 이유가 사라진다.
 */
final class TrustedProxies {

    private static final Logger log = LoggerFactory.getLogger(TrustedProxies.class);

    /** 아무도 믿지 않는다 — 헤더는 전부 무시되고 {@code getRemoteAddr()} 만 쓰인다. */
    static final TrustedProxies NONE = new TrustedProxies(List.of());

    private final List<Cidr> blocks;

    private TrustedProxies(List<Cidr> blocks) {
        this.blocks = blocks;
    }

    /**
     * {@code 127.0.0.1} · {@code ::1} · {@code 10.0.0.0/8} 같은 표기를 파싱한다.
     *
     * <p>접두 길이를 생략하면 단일 주소({@code /32}, IPv6 는 {@code /128})다.
     * 해석할 수 없는 항목은 <b>버린다</b> — 여기서 예외를 던지면 설정 오타 하나가
     * 애플리케이션 기동 실패가 되고, 그 대가가 오타 자체보다 크다. 대신 경고를 남긴다.
     * 버려진 항목은 "믿지 않는다" 쪽으로 떨어지므로 <b>안전한 방향</b>의 실패다.
     */
    static TrustedProxies parse(List<String> entries) {
        if (entries == null || entries.isEmpty()) {
            return NONE;
        }
        List<Cidr> parsed = new ArrayList<>(entries.size());
        for (String entry : entries) {
            Cidr cidr = Cidr.parse(entry);
            if (cidr == null) {
                log.warn("[rate limit] 신뢰 프록시 목록의 항목을 해석하지 못해 무시한다: {}", entry);
                continue;
            }
            parsed.add(cidr);
        }
        return parsed.isEmpty() ? NONE : new TrustedProxies(parsed);
    }

    /** 이 주소가 신뢰 프록시인가. 해석되지 않는 주소는 <b>항상 false</b> 다. */
    boolean contains(String address) {
        if (blocks.isEmpty()) {
            return false;
        }
        byte[] bytes = toBytes(address);
        if (bytes == null) {
            return false;
        }
        for (Cidr block : blocks) {
            if (block.matches(bytes)) {
                return true;
            }
        }
        return false;
    }

    /**
     * IP 리터럴만 바이트로 바꾼다. <b>DNS 조회를 하지 않는다</b> — 요청이 준 문자열로
     * 이름 해석을 돌면 그 자체가 외부에서 조종되는 네트워크 호출이 된다.
     */
    private static byte[] toBytes(String address) {
        if (address == null) {
            return null;
        }
        String literal = address.trim();
        if (literal.isEmpty()) {
            return null;
        }
        // [::1]:1234 같은 표기와 IPv6 존 인덱스(fe80::1%eth0)를 걷어낸다.
        if (literal.startsWith("[")) {
            int end = literal.indexOf(']');
            if (end < 0) {
                return null;
            }
            literal = literal.substring(1, end);
        }
        int zone = literal.indexOf('%');
        if (zone >= 0) {
            literal = literal.substring(0, zone);
        }
        if (!looksLikeIpLiteral(literal)) {
            return null;
        }
        try {
            return InetAddress.getByName(literal).getAddress();
        } catch (UnknownHostException e) {
            return null;
        }
    }

    /** 숫자·점·콜론·16진수만. 이 검사를 통과한 문자열에는 {@code getByName} 이 DNS 를 쓰지 않는다. */
    private static boolean looksLikeIpLiteral(String value) {
        for (int i = 0; i < value.length(); i++) {
            char c = value.charAt(i);
            boolean allowed = (c >= '0' && c <= '9')
                    || (c >= 'a' && c <= 'f')
                    || (c >= 'A' && c <= 'F')
                    || c == '.' || c == ':';
            if (!allowed) {
                return false;
            }
        }
        return !value.isEmpty();
    }

    private record Cidr(byte[] network, int prefixBits) {

        static Cidr parse(String entry) {
            if (entry == null || entry.isBlank()) {
                return null;
            }
            String trimmed = entry.trim();
            int slash = trimmed.lastIndexOf('/');
            String host = slash < 0 ? trimmed : trimmed.substring(0, slash);
            byte[] network = toBytes(host);
            if (network == null) {
                return null;
            }
            int bits = network.length * 8;
            if (slash >= 0) {
                try {
                    bits = Integer.parseInt(trimmed.substring(slash + 1).trim());
                } catch (NumberFormatException e) {
                    return null;
                }
                if (bits < 0 || bits > network.length * 8) {
                    return null;
                }
            }
            return new Cidr(network, bits);
        }

        boolean matches(byte[] address) {
            // IPv4 와 IPv6 를 섞어 비교하지 않는다. 자바가 IPv4 매핑 주소(::ffff:1.2.3.4)를
            // 이미 4바이트로 돌려주므로 길이가 곧 계열이다.
            if (address.length != network.length) {
                return false;
            }
            int fullBytes = prefixBits / 8;
            for (int i = 0; i < fullBytes; i++) {
                if (address[i] != network[i]) {
                    return false;
                }
            }
            int remainingBits = prefixBits % 8;
            if (remainingBits == 0) {
                return true;
            }
            int mask = 0xFF << (8 - remainingBits);
            return (address[fullBytes] & mask) == (network[fullBytes] & mask);
        }
    }
}
