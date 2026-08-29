package com.heattrip.heat_trip_backend.S3.media.error;

import io.swagger.v3.oas.annotations.media.Schema;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.Instant;
import java.util.NoSuchElementException;

/**
 * 전역 예외 처리기. [①]
 * - 컨트롤러에서 던진 예외를 일관된 JSON 구조로 변환해 반환합니다. [②]
 * - Swagger/OpenAPI에서 4xx/5xx 응답 스키마를 명확히 보여줄 수 있습니다. [③]
 */
@RestControllerAdvice // [A] 전역 @Controller/~를 가로채 JSON 응답으로 바꿔줌
public class GlobalExceptionHandler {

    private static final org.slf4j.Logger log =
            org.slf4j.LoggerFactory.getLogger(GlobalExceptionHandler.class);

    /**
     * 오류 응답 페이로드(record). [④]
     * - Swagger에서 스키마 이름을 지정해 문서화합니다. [⑤]
     */
    @Schema(name = "ErrorResponse") // [B] OpenAPI 문서에 모델 이름으로 노출
    public record ErrorResponse(
        int status,        // HTTP status code (예: 400, 404, 500)
        String error,      // 상태 텍스트 (예: "Bad Request")
        String message,    // 구체 메시지 (예외 메시지)
        String path,       // 요청 URI
        Instant timestamp  // 서버 기준 발생 시각
    ) { }

    /**
     * 400 Bad Request 매핑. [⑥]
     * - 검증 실패/잘못된 파라미터 등 클라이언트 오류.
     */
    @ExceptionHandler(IllegalArgumentException.class) // [C] 해당 타입 예외만 처리
    public ResponseEntity<ErrorResponse> handleBadRequest(
        IllegalArgumentException ex,
        org.springframework.web.context.request.WebRequest req // [D] URI 등 접근
    ) {
        var body = new ErrorResponse(
            HttpStatus.BAD_REQUEST.value(),
            "Bad Request",
            ex.getMessage(),
            req.getDescription(false).replace("uri=", ""), // "uri=/path" 문자열 정리
            Instant.now()
        );
        return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(body);
    }

    /**
     * 404 Not Found 매핑. [⑦]
     * - repo.findById(...).orElseThrow() → NoSuchElementException 등.
     */
    @ExceptionHandler(NoSuchElementException.class)
    public ResponseEntity<ErrorResponse> handleNotFound(
        Exception ex, org.springframework.web.context.request.WebRequest req
    ) {
        var body = new ErrorResponse(
            HttpStatus.NOT_FOUND.value(),
            "Not Found",
            ex.getMessage(),
            req.getDescription(false).replace("uri=", ""),
            Instant.now()
        );
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(body);
    }

    /**
     * 403 Forbidden 매핑(선택). [⑧]
     * - 권한 부족(인가 실패) 상황.
     */
    @ExceptionHandler(org.springframework.security.access.AccessDeniedException.class)
    public ResponseEntity<ErrorResponse> handleForbidden(
        Exception ex, org.springframework.web.context.request.WebRequest req
    ) {
        var body = new ErrorResponse(
            HttpStatus.FORBIDDEN.value(),
            "Forbidden",
            ex.getMessage(),
            req.getDescription(false).replace("uri=", ""),
            Instant.now()
        );
        return ResponseEntity.status(HttpStatus.FORBIDDEN).body(body);
    }

    /**
     * 401 Unauthorized 매핑. [⑩]
     *
     * <p>인증 주체를 해석할 수 없을 때({@code CurrentUserArgumentResolver}). 본문 없이 401 만 돌려줘
     * {@code SecurityConfig} 의 {@code HttpStatusEntryPoint(UNAUTHORIZED)} 와 형태를 맞춘다 —
     * "토큰 없음"과 "탈퇴한 계정의 살아 있는 토큰"이 앱에게 같은 모양으로 보여야 한다. (이슈 #5)
     *
     * <p><b>이 핸들러는 반드시 이 클래스 안에 있어야 한다.</b> 별도 {@code @ControllerAdvice} 로
     * 빼면 예외 구체성이 아니라 <b>advice 빈 순서</b>로 승자가 정해져서, 순서가 뒤면 아래
     * {@code @ExceptionHandler(Exception.class)} 가 먼저 잡아 500 이 그대로 나간다(실측 확인).
     * 같은 클래스 안에서는 {@code ExceptionDepthComparator} 가 더 구체적인 이쪽을 고른다.
     *
     * <p>메시지를 본문에 싣지 않는 이유는 아래 {@code handleBadRequest} 를 보면 된다 —
     * {@code ex.getMessage()} 가 그대로 응답이 된다. 인증 실패 경로에서 그건 유출이다. (이슈 #6)
     */
    @ExceptionHandler(com.heattrip.heat_trip_backend.OAuth.principal.UnauthenticatedException.class)
    public ResponseEntity<Void> handleUnauthenticated() {
        return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
    }

    /**
     * 컨트롤러가 상태 코드를 <b>스스로 정해</b> 던진 예외를 그대로 내보낸다. [⑪]
     *
     * <p>이게 없으면 {@code new ResponseStatusException(HttpStatus.FORBIDDEN, ...)} 이
     * 아래 {@code @ExceptionHandler(Exception.class)} 에 먼저 잡혀 <b>500</b> 으로 나간다.
     * 401·403·404 를 의도한 코드가 전부 500 이었다(실측 확인). 계약(openapi.yaml)이
     * 선언한 응답 코드와 실제가 어긋났고, 앱은 "권한 없음"과 "서버 고장"을 구분할 수 없었다.
     *
     * <p>{@code NoResourceFoundException}(알 수 없는 경로)도 함께 받는다.
     * <b>그건 {@code ResponseStatusException} 의 하위 타입이 아니다</b> — Spring 6.1 에서
     * {@code ServletException} 을 상속하고 {@code ErrorResponse} 를 구현한다. 그래서 타입을
     * 둘 다 적어야 하고, 상태 코드는 공통 인터페이스 {@code ErrorResponse.getStatusCode()}
     * 에서 읽는다. 이걸 빼면 알 수 없는 경로가 500 이 된다(실측 확인).
     *
     * <p><b>메시지로 {@code getReason()} 만 쓴다.</b> 그건 던진 사람이 고른 문구라 밖에
     * 내보내도 되는 값이다. {@code getMessage()} 는 상태 코드·내부 문구가 섞인 조합이라
     * {@code "403 FORBIDDEN \"...\""} 같은 값이 클라이언트로 나간다.
     */
    @ExceptionHandler({
        org.springframework.web.server.ResponseStatusException.class,
        org.springframework.web.servlet.resource.NoResourceFoundException.class
    })
    public ResponseEntity<ErrorResponse> handleDeclaredStatus(
        Exception ex,
        org.springframework.web.context.request.WebRequest req
    ) {
        // 두 예외의 유일한 공통 조상은 Exception 이다. 상태 코드는 둘 다 구현하는
        // ErrorResponse 인터페이스에서 읽는다.
        HttpStatus status = HttpStatus.resolve(((org.springframework.web.ErrorResponse) ex).getStatusCode().value());
        if (status == null) {
            status = HttpStatus.INTERNAL_SERVER_ERROR;
        }
        String reason = (ex instanceof org.springframework.web.server.ResponseStatusException rse)
                ? rse.getReason()
                : "요청한 경로를 찾을 수 없습니다.";

        var body = new ErrorResponse(
            status.value(),
            status.getReasonPhrase(),
            reason,
            req.getDescription(false).replace("uri=", ""),
            Instant.now()
        );
        return ResponseEntity.status(status).body(body);
    }

    /**
     * <b>형식이 깨진 요청</b>을 500 이 아니라 제 코드로 내보낸다. [⑫] (이슈 #9)
     *
     * <p>여기 오는 세 예외는 전부 "서버가 고장난 것" 이 아니라 "요청이 규격에 맞지 않는 것"
     * 이다. 그런데 핸들러가 없으면 아래 {@code @ExceptionHandler(Exception.class)} 가 잡아
     * <b>전부 500</b> 이 된다. 실측한 것: {@code POST /auth/token/refresh} 에 깨진 JSON
     * ({@code "{"}), 배열 본문({@code "[]"}), {@code Content-Type} 없음, {@code text/plain},
     * {@code GET} 메서드 — 다섯 경우 모두 500 이었다. {@code /auth/login}·{@code /auth/signup}
     * 도 같았다.
     *
     * <p>이게 왜 인증 경로에서 특히 나쁜가: {@code /auth/token/refresh} 는 비인증 공개
     * 경로이고 계약({@code openapi.yaml})은 그 오퍼레이션의 응답으로 200·400·401·415 만
     * 선언한다. 500 은 계약에 없는 코드이며, 앱은 "다시 로그인하라"와 "서버가 고장났다"를
     * 구분할 수 없다 — 후자로 읽으면 재시도 루프를 돈다.
     *
     * <p><b>{@code ex.getMessage()} 를 본문에 싣지 않는다.</b> Jackson 의 파싱 실패 메시지에는
     * 요청 본문 조각이 그대로 섞여 들어온다. 그 본문이 refresh 토큰 원문인 경로에서 그건
     * 곧 유출이다(#6). 원인은 로그에도 남기지 않는다 — 같은 이유다.
     *
     * <p><b>이 핸들러도 반드시 이 클래스 안에 있어야 한다.</b> 별도 advice 로 빼면 예외
     * 구체성이 아니라 advice 빈 순서로 승자가 정해져 catch-all 이 먼저 잡는다(#44 에서 실측).
     */
    @ExceptionHandler({
        org.springframework.http.converter.HttpMessageNotReadableException.class,
        org.springframework.web.HttpMediaTypeNotSupportedException.class,
        org.springframework.web.HttpRequestMethodNotSupportedException.class
    })
    public ResponseEntity<ErrorResponse> handleMalformedRequest(
        Exception ex, org.springframework.web.context.request.WebRequest req
    ) {
        final HttpStatus status;
        final String message;
        if (ex instanceof org.springframework.web.HttpMediaTypeNotSupportedException) {
            status = HttpStatus.UNSUPPORTED_MEDIA_TYPE;
            message = "지원하지 않는 Content-Type 입니다.";
        } else if (ex instanceof org.springframework.web.HttpRequestMethodNotSupportedException) {
            status = HttpStatus.METHOD_NOT_ALLOWED;
            message = "이 경로가 지원하지 않는 HTTP 메서드입니다.";
        } else {
            status = HttpStatus.BAD_REQUEST;
            message = "요청 본문을 읽을 수 없습니다.";
        }

        var body = new ErrorResponse(
            status.value(),
            status.getReasonPhrase(),
            message,
            req.getDescription(false).replace("uri=", ""),
            Instant.now()
        );
        return ResponseEntity.status(status).body(body);
    }

    /**
     * 500 Internal Server Error 매핑. [⑨]
     * - 마지막 안전망: 처리되지 않은 모든 예외.
     *
     * <p><b>예외 메시지를 본문에 싣지 않는다.</b> 여기 오는 것은 우리가 예상하지 못한
     * 예외이고, 그 메시지에는 SQL 조각·파일 경로·이메일·토큰 조각이 섞여 들어올 수 있다
     * (이슈 #6). 실제로 {@code "User not found: " + email} 이 이 경로로 이메일을
     * 내보내고 있었다. 원인은 서버 로그에만 남기고, 응답에는 상관관계 ID 만 준다 —
     * 그것으로 로그에서 이 요청을 정확히 찾을 수 있다.
     */
    @ExceptionHandler(Exception.class) // [E] 상위 캐치
    public ResponseEntity<ErrorResponse> handleEtc(
        Exception ex, org.springframework.web.context.request.WebRequest req
    ) {
        String path = req.getDescription(false).replace("uri=", "");
        String correlationId = org.slf4j.MDC.get(
                com.heattrip.heat_trip_backend.observability.logging.CorrelationIdFilter.MDC_KEY);

        log.error("처리되지 않은 예외 — {} {}", req.getDescription(false), ex.getClass().getName(), ex);

        var body = new ErrorResponse(
            HttpStatus.INTERNAL_SERVER_ERROR.value(),
            "Internal Server Error",
            correlationId == null
                    ? "서버에서 오류가 발생했습니다."
                    : "서버에서 오류가 발생했습니다. (요청 ID: " + correlationId + ")",
            path,
            Instant.now()
        );
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(body);
    }
}

/* ─────────────────────────── 주석 참고(footnotes) ───────────────────────────
[①] 전역 예외 처리기: 컨트롤러 계층 전반의 예외를 한 곳에서 포맷統一.
[②] 일관된 JSON: 클라이언트/프런트가 에러 처리 로직을 단순화 가능.
[③] OpenAPI 문서: 각 상태코드별 에러 바디 구조를 명세화.

[A] @RestControllerAdvice: @ControllerAdvice + @ResponseBody 역할.
[④] record: 불변/간결 데이터 캐리어. Swagger와 궁합 좋음.
[⑤] @Schema(name=...): 문서 스키마 이름 고정(재사용·가독성 ↑).

[⑥] 400: 유효성/MIME/사이즈/형식 오류 등 클라이언트 과실.
[⑦] 404: 리소스 미존재(엔티티 없음) 매핑.
[⑧] 403: 인증은 되었으나 권한 부족.
[⑨] 500: 내부 처리 중 예기치 못한 오류(운영 시 로깅/트레이싱 권장).
[⑩] 401: 인증 주체 해석 실패. 본문 없이 상태 코드만 — 메시지를 실으면 그게 유출 경로가 된다(#5·#6).
[⑪] ResponseStatusException: 컨트롤러가 스스로 정한 상태 코드. catch-all 보다 먼저 잡아야 한다(#44).
[⑫] 400/415/405: 형식이 깨진 요청. 핸들러가 없으면 전부 500 이었다(#9 에서 실측). 본문에 예외 메시지 금지 — 요청 본문 조각이 섞인다(#6).
────────────────────────────────────────────────────────────────────────── */
