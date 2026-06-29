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
     * 500 Internal Server Error 매핑. [⑨]
     * - 마지막 안전망: 처리되지 않은 모든 예외.
     */
    @ExceptionHandler(Exception.class) // [E] 상위 캐치
    public ResponseEntity<ErrorResponse> handleEtc(
        Exception ex, org.springframework.web.context.request.WebRequest req
    ) {
        var body = new ErrorResponse(
            HttpStatus.INTERNAL_SERVER_ERROR.value(),
            "Internal Server Error",
            ex.getMessage(),
            req.getDescription(false).replace("uri=", ""),
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
────────────────────────────────────────────────────────────────────────── */
