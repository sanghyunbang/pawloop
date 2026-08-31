package com.heattrip.heat_trip_backend.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ReadListener;
import jakarta.servlet.ServletException;
import jakarta.servlet.ServletInputStream;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletRequestWrapper;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * 채팅 메시지 본문이 너무 크면 <b>읽기 전에</b> 거절한다. (이슈 #129 · #78 이 넘기고 #80 이 넘긴 것)
 *
 * <h2>무엇이 문제였나</h2>
 * <p>{@code ChatRoomService.validBody} 는 본문을 <b>다 읽은 뒤</b> 컬럼 폭(65,535바이트)으로
 * 거절한다. 20MB 본문을 던지면 그것을 전부 {@code String} 으로 올린 뒤 400 을 낸다 —
 * <b>실측 404ms</b> 다.
 *
 * <p>앞에서 막는 것은 운영 nginx 의 {@code client_max_body_size} 하나뿐이었고, 그건 이 저장소의
 * 애플리케이션 설정이 아니다. nginx 없이 뜨는 모든 환경에서는 아무것도 안 막았다.
 *
 * <p>그리고 #80 이 붙인 rate limit 은 이것을 막지 못한다 — 분당 60건 × 20MB 다.
 *
 * <h2>두 겹으로 막는다</h2>
 * <ol>
 *   <li><b>{@code Content-Length}</b> — 있으면 O(1) 로 끝난다. 본문을 한 바이트도 안 읽는다.</li>
 *   <li><b>세면서 읽기</b> — 헤더가 없거나(chunked) 거짓일 수 있다. 헤더는 보내는 쪽이 적는
 *       문자열이라 그 자체로는 아무것도 증명하지 않는다. 그래서 실제로 읽히는 바이트를 센다.</li>
 * </ol>
 *
 * <p>2번에서 한도를 넘기면 {@link IOException} 을 던진다. 스프링의 메시지 변환기가 그것을
 * {@code HttpMessageNotReadableException} 으로 감싸고, {@code GlobalExceptionHandler} 가 그것을
 * <b>이미 400 계약으로</b> 다룬다 — 새 핸들러가 필요 없다.
 *
 * <h2>왜 이 경로만인가</h2>
 * <p>미디어 업로드({@code /media/**})는 <b>원래 큰 파일을 받는다.</b> 전역 상한을 걸면 그쪽이
 * 깨진다. 채팅 본문은 컬럼이 65,535바이트라 상한이 명확한 자리이고, 그래서 여기만 막는다.
 *
 * <h2>413 이 아니라 400 인 이유</h2>
 * <p>같은 경로에서 본문 길이를 거절하는 자리가 이미 있고({@code validBody}) 그쪽이 400 이다.
 * 여기만 413 으로 두면 <b>같은 이유의 거절이 크기에 따라 다른 코드</b>가 되어 앱이 두 가지를
 * 다뤄야 한다. 계약({@code openapi.yaml})을 안 바꾸는 것이 이 이슈의 범위다.
 */
@Component
public class ChatBodySizeLimitFilter extends OncePerRequestFilter {

    /**
     * 요청 본문의 상한. <b>컬럼 폭이 아니라 HTTP 본문의 상한이다.</b>
     *
     * <p>256 KiB 인 근거. {@code chat_message.body} 는 65,535<b>바이트</b>이고, 한글은 JSON 에서
     * 이스케이프가 없어 그대로 65,535바이트다. 여기에 {@code clientMsgId}(22자) ·
     * {@code contentType} · 키 이름을 더해도 약 66KB 다. <b>정상 최대의 네 배</b>를 준다.
     *
     * <p><b>솔직하게 적는 한계.</b> 제어문자로만 채운 본문은 JSON 에서 한 글자가
     * {@code \\u0000}(6바이트)로 부풀어 65,535바이트 텍스트가 393KB 가 될 수 있다. 그런 요청은
     * 여기서 걸린다 — {@code validBody} 의 판정과 다른 결과다. 그 입력을 정상으로 볼 이유가
     * 없다고 보고 좁은 쪽을 골랐다.
     *
     * <p>이 값을 늘리려면 왜 늘리는지 적어라. 늘리는 만큼 힙으로 올라가는 바이트가 늘어난다.
     */
    static final int MAX_REQUEST_BYTES = 256 * 1024;

    /** {@code POST /api/chat/rooms/{id}/messages}. */
    private static final String MESSAGES_PATH = "^/api/chat/rooms/[0-9]+/messages$";

    /** {@code POST /api/chat/rooms/{id}/reports}. (#82) */
    private static final String REPORTS_PATH = "^/api/chat/rooms/[0-9]+/reports$";

    private static final String CODE = "PAYLOAD_TOO_LARGE";
    private static final String MESSAGE = "메시지가 너무 깁니다.";

    private final ErrorBodyWriter errors;

    public ChatBodySizeLimitFilter(ObjectMapper objectMapper) {
        this.errors = new ErrorBodyWriter(objectMapper);
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
                                    FilterChain filterChain) throws ServletException, IOException {
        if (!isChatWrite(request)) {
            filterChain.doFilter(request, response);
            return;
        }

        // ① 헤더가 스스로 밝힌 크기. 있으면 본문을 한 바이트도 안 읽고 끝난다.
        if (request.getContentLengthLong() > MAX_REQUEST_BYTES) {
            errors.badRequest(response, CODE, MESSAGE);
            return;
        }

        // ② 헤더가 없거나 거짓일 수 있다. 실제로 읽히는 바이트를 센다.
        filterChain.doFilter(new LimitedBodyRequest(request, MAX_REQUEST_BYTES), response);
    }

    /**
     * 본문을 받는 채팅 경로.
     *
     * <p>신고({@code /reports})가 여기 있는 이유(#82): {@code ChatReportService} 가 사유를
     * 500자에서 자르는데 그건 <b>파싱이 끝난 뒤</b>다. 20MB 사유를 보내면 그것을 전부 힙에
     * 올린 뒤에 자른다 — {@code validBody} 가 그랬던 것과 <b>같은 구멍</b>이다.
     */
    private static boolean isChatWrite(HttpServletRequest request) {
        String path = request.getRequestURI();
        if (!"POST".equals(request.getMethod()) || path == null) {
            return false;
        }
        return path.matches(MESSAGES_PATH) || path.matches(REPORTS_PATH);
    }

    /** 본문을 세면서 읽는 요청. 한도를 넘기면 그 자리에서 던진다. */
    private static final class LimitedBodyRequest extends HttpServletRequestWrapper {

        private final int limit;

        LimitedBodyRequest(HttpServletRequest request, int limit) {
            super(request);
            this.limit = limit;
        }

        @Override
        public ServletInputStream getInputStream() throws IOException {
            return new CountingStream(super.getInputStream(), limit);
        }
    }

    /**
     * 읽은 바이트를 세는 스트림.
     *
     * <p>버퍼에 담아 두지 않는다 — 담으면 막으려던 메모리를 그대로 쓰게 된다.
     * <b>흘려보내면서 세기만 한다.</b>
     */
    private static final class CountingStream extends ServletInputStream {

        private final ServletInputStream delegate;
        private final int limit;
        private long read;

        CountingStream(ServletInputStream delegate, int limit) {
            this.delegate = delegate;
            this.limit = limit;
        }

        private void countOrThrow(int justRead) throws IOException {
            if (justRead <= 0) {
                return;
            }
            read += justRead;
            if (read > limit) {
                // 메시지 변환기가 HttpMessageNotReadableException 으로 감싸고
                // GlobalExceptionHandler 가 400 계약으로 다룬다.
                throw new IOException(MESSAGE);
            }
        }

        @Override
        public int read() throws IOException {
            int value = delegate.read();
            countOrThrow(value < 0 ? 0 : 1);
            return value;
        }

        @Override
        public int read(byte[] buffer, int offset, int length) throws IOException {
            int count = delegate.read(buffer, offset, length);
            countOrThrow(count);
            return count;
        }

        @Override
        public boolean isFinished() {
            return delegate.isFinished();
        }

        @Override
        public boolean isReady() {
            return delegate.isReady();
        }

        @Override
        public void setReadListener(ReadListener listener) {
            delegate.setReadListener(listener);
        }

        @Override
        public void close() throws IOException {
            delegate.close();
        }
    }
}
