package com.heattrip.heat_trip_backend.S3.media;

import com.heattrip.heat_trip_backend.S3.UploadCategory;
import com.heattrip.heat_trip_backend.S3.media.dto.MediaItemResponse;
import com.heattrip.heat_trip_backend.S3.media.dto.UrlResponse;
import com.heattrip.heat_trip_backend.S3.media.error.GlobalExceptionHandler.ErrorResponse; // [①] 에러 스키마 참조

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.*;
import io.swagger.v3.oas.annotations.responses.*;
import io.swagger.v3.oas.annotations.tags.Tag;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;

import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.time.Duration;
import java.util.List;

/**
 * 범용 미디어 API 컨트롤러. [②]
 * - DTO 반환으로 Swagger 스키마를 명확화합니다. [③]
 * - 메서드별 @Operation/@ApiResponses로 문서 가독성을 높입니다. [④]
 */
@Tag(name = "Media", description = "Generic media upload/read/replace/delete API") // [A] Swagger 그룹 태깅
@RestController
@RequestMapping("/media")
@Validated // [B] Bean Validation(@Min/@Max 등) 활성화
public class MediaController {

    private final MediaService mediaService; // [⑤] 도메인 서비스(저장소/JPA/권한 포함)
    public MediaController(MediaService mediaService) { this.mediaService = mediaService; }

    // ─────────────────────────────────────────────────────────────────────
    // C: 멀티 파일 업로드
    // ─────────────────────────────────────────────────────────────────────
    @Operation(
        summary = "Upload multiple files",
        description = "Uploads multiple files to S3 and returns stored metadata and public URLs.", // [C]
        security = { @SecurityRequirement(name = "bearerAuth") } // [D] Swagger UI에서 Bearer 토큰 필요
    )
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Uploaded",
            content = @Content(mediaType = "application/json",
                array = @ArraySchema(schema = @Schema(implementation = MediaItemResponse.class)))),

        // ▼ 에러 스키마 매핑(문서화)
        @ApiResponse(responseCode = "400", description = "Bad request",
            content = @Content(mediaType = "application/json",
                schema = @Schema(implementation = ErrorResponse.class))),
        @ApiResponse(responseCode = "401", description = "Unauthorized",
            content = @Content(mediaType = "application/json",
                schema = @Schema(implementation = ErrorResponse.class))),
        @ApiResponse(responseCode = "500", description = "Internal Server Error",
            content = @Content(mediaType = "application/json",
                schema = @Schema(implementation = ErrorResponse.class)))
    })
    @PostMapping(consumes = MediaType.MULTIPART_FORM_DATA_VALUE, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<List<MediaItemResponse>> upload(
        @Parameter(description = "Files to upload") // [E] Swagger에서 파일 선택 UI 생성
        @RequestPart("files") List<MultipartFile> files,
        @Parameter(description = "Upload category")
        @RequestParam(name = "category") UploadCategory category, // [F] Enum → 문서에서 선택형
        @RequestParam(name = "refType", required = false) String refType, // [G] 도메인 연결 메타
        @RequestParam(name = "refId",   required = false) String refId,
        @AuthenticationPrincipal String userId // [H] JWT 필터에서 주입되는 사용자 식별자 가정
    ) {
        var saved = mediaService.uploadMany(files, category, userId, refType, refId); // [I] 업로드+저장
        var body = saved.stream().map(m -> new MediaItemResponse(
            m.getId(),
            m.getObjectKey(),                                 // S3 object key
            mediaService.publicUrl(m.getObjectKey()),         // [J] CDN 공개 URL 조립
            m.getContentType(),
            m.getSize(),
            m.getCategory(),
            m.getRefType(),
            m.getRefId()
        )).toList();
        return ResponseEntity.ok(body); // [K] 200 OK + DTO 리스트
    }

    // ─────────────────────────────────────────────────────────────────────
    // R: 공개 URL 조립 (공개 배포)
    // ─────────────────────────────────────────────────────────────────────
    @Operation(
        summary = "Build a public URL",
        description = "Returns a public (or CDN) URL assembled from the given S3 object key." // [L]
    )
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "OK",
            content = @Content(schema = @Schema(implementation = UrlResponse.class))),
        @ApiResponse(responseCode = "400", description = "Bad request",
            content = @Content(mediaType = "application/json",
                schema = @Schema(implementation = ErrorResponse.class))),
        @ApiResponse(responseCode = "500", description = "Internal Server Error",
            content = @Content(mediaType = "application/json",
                schema = @Schema(implementation = ErrorResponse.class)))
    })
    @GetMapping(path = "/url", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<UrlResponse> getPublicUrl(
        @Parameter(description = "S3 object key", required = true)
        @RequestParam(name = "key") String objectKey // [M] 파라미터명 'key' 유지(클라 호환)
    ) {
        return ResponseEntity.ok(new UrlResponse(mediaService.publicUrl(objectKey)));
    }

    // ─────────────────────────────────────────────────────────────────────
    // R: 프리사인드 URL 발급 (비공개 배포)
    // ─────────────────────────────────────────────────────────────────────
    @Operation(
        summary = "Issue a presigned URL",
        description = "Issues a time-limited presigned URL for private delivery." // [N]
    )
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "OK",
            content = @Content(schema = @Schema(implementation = UrlResponse.class))),
        @ApiResponse(responseCode = "400", description = "Bad request",
            content = @Content(mediaType = "application/json",
                schema = @Schema(implementation = ErrorResponse.class))),
        @ApiResponse(responseCode = "500", description = "Internal Server Error",
            content = @Content(mediaType = "application/json",
                schema = @Schema(implementation = ErrorResponse.class)))
    })
    @GetMapping(path = "/presigned", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<UrlResponse> getPresigned(
        @Parameter(description = "S3 object key", required = true)
        @RequestParam(name = "key") String objectKey,
        @Parameter(description = "Expiration in minutes (1~120)") // [O] 제약 문서화
        @RequestParam(name = "minutes", defaultValue = "10") @Min(1) @Max(120) int minutes // [P] Bean Validation
    ) {
        var url = mediaService.presignedUrl(objectKey, Duration.ofMinutes(minutes));
        return ResponseEntity.ok(new UrlResponse(url));
    }

    // ─────────────────────────────────────────────────────────────────────
    // U: 파일 교체
    // ─────────────────────────────────────────────────────────────────────
    @Operation(
        summary = "Replace a file",
        description = "Replaces the stored file for a given media id and returns updated metadata.",
        security = { @SecurityRequirement(name = "bearerAuth") }
    )
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Replaced",
            content = @Content(schema = @Schema(implementation = MediaItemResponse.class))),
        @ApiResponse(responseCode = "400", description = "Bad request",
            content = @Content(mediaType = "application/json",
                schema = @Schema(implementation = ErrorResponse.class))),
        @ApiResponse(responseCode = "401", description = "Unauthorized",
            content = @Content(mediaType = "application/json",
                schema = @Schema(implementation = ErrorResponse.class))),
        @ApiResponse(responseCode = "404", description = "Media not found",
            content = @Content(mediaType = "application/json",
                schema = @Schema(implementation = ErrorResponse.class))),
        @ApiResponse(responseCode = "500", description = "Internal Server Error",
            content = @Content(mediaType = "application/json",
                schema = @Schema(implementation = ErrorResponse.class)))
    })
    @PutMapping(path = "/{mediaId}",
                consumes = MediaType.MULTIPART_FORM_DATA_VALUE,
                produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<MediaItemResponse> replace(
        @Parameter(description = "Media id (DB PK)", required = true)
        @PathVariable(name = "mediaId") @Min(1) Long mediaId, // [Q] 파라미터 검증
        @Parameter(description = "New file")
        @RequestPart("file") MultipartFile file,
        @AuthenticationPrincipal String userId
    ) {
        var m = mediaService.replace(mediaId, file, userId);
        return ResponseEntity.ok(new MediaItemResponse(
            m.getId(),
            m.getObjectKey(),
            mediaService.publicUrl(m.getObjectKey()),
            m.getContentType(),
            m.getSize(),
            m.getCategory(),
            m.getRefType(),
            m.getRefId()
        ));
    }

    // ─────────────────────────────────────────────────────────────────────
    // D: 단건 삭제
    // ─────────────────────────────────────────────────────────────────────
    @Operation(
        summary = "Delete a media by id",
        description = "Soft/hard deletes a media item.", // [R] 실제 구현은 하드+S3 삭제
        security = { @SecurityRequirement(name = "bearerAuth") }
    )
    @ApiResponses({
        @ApiResponse(responseCode = "204", description = "Deleted"),
        @ApiResponse(responseCode = "401", description = "Unauthorized",
            content = @Content(mediaType = "application/json",
                schema = @Schema(implementation = ErrorResponse.class))),
        @ApiResponse(responseCode = "404", description = "Media not found",
            content = @Content(mediaType = "application/json",
                schema = @Schema(implementation = ErrorResponse.class))),
        @ApiResponse(responseCode = "500", description = "Internal Server Error",
            content = @Content(mediaType = "application/json",
                schema = @Schema(implementation = ErrorResponse.class)))
    })
    @DeleteMapping("/{mediaId}")
    public ResponseEntity<Void> delete(
        @Parameter(description = "Media id (DB PK)", required = true)
        @PathVariable(name = "mediaId") @Min(1) Long mediaId,
        @AuthenticationPrincipal String userId
    ) {
        mediaService.delete(mediaId, userId);
        return ResponseEntity.noContent().build(); // [S] 204 No Content
    }

    // ─────────────────────────────────────────────────────────────────────
    // D: 연결 리소스 전체 삭제 (refType+refId 기준)
    // ─────────────────────────────────────────────────────────────────────
    @Operation(
        summary = "Delete all media by reference",
        description = "Deletes all media items associated with (refType, refId).", // [T]
        security = { @SecurityRequirement(name = "bearerAuth") }
    )
    @ApiResponses({
        @ApiResponse(responseCode = "204", description = "Deleted"),
        @ApiResponse(responseCode = "401", description = "Unauthorized",
            content = @Content(mediaType = "application/json",
                schema = @Schema(implementation = ErrorResponse.class))),
        @ApiResponse(responseCode = "500", description = "Internal Server Error",
            content = @Content(mediaType = "application/json",
                schema = @Schema(implementation = ErrorResponse.class)))
    })
    @DeleteMapping
    public ResponseEntity<Void> deleteByRef(
        @Parameter(description = "Reference type", required = true)
        @RequestParam(name = "refType") String refType,
        @Parameter(description = "Reference id", required = true)
        @RequestParam(name = "refId") String refId,
        @AuthenticationPrincipal String userId
    ) {
        mediaService.deleteByRef(refType, refId, userId);
        return ResponseEntity.noContent().build();
    }
}

/* ─────────────────────────── 주석 참고(footnotes) ───────────────────────────
[①] 에러 스키마 참조: ErrorResponse를 @ApiResponse의 schema로 재사용.
[②] 컨트롤러 목적: 업로드/읽기/교체/삭제의 범용 미디어 API.
[③] DTO 반환: Map 대신 DTO(Record) → Swagger 스키마가 명확해짐.
[④] 풍부한 메타데이터: summary/description/security/response 스키마 명세.

[A] @Tag: Swagger UI에서 그룹 탭/정렬에 활용.
[B] @Validated: 메서드 파라미터에 Bean Validation 적용(@Min/@Max 등).
[⑤] MediaService: 저장소(S3)와 JPA 리포지토리, 권한 검사 캡슐화.

[C] 업로드 설명: 다중 파일 업로드 후 저장 메타 반환.
[D] SecurityRequirement: @SecurityScheme(name="bearerAuth")와 연결(OpenApiConfig 참고).
[E] @RequestPart: multipart/form-data에서 파일 업로드 필드.
[F] Enum 파라미터: Swagger에서 드롭다운으로 표시.
[G] refType/refId: 도메인 연결 메타(선택 필드).
[H] @AuthenticationPrincipal: JWT 인증 필터가 SecurityContext에 저장한 사용자 식별자 주입.
[I] 서비스 호출: 파일 검증/업로드/DB 저장 일괄 처리.
[J] 공개 URL: S3 key → CloudFront 등 CDN 경로 조합.
[K] 반환 DTO 리스트: Swagger에서 array[MediaItemResponse]로 표시.

[L] 공개 URL 조립: 단순 키 → URL 변환 API.
[M] key 파라미터명 유지: 기존 클라이언트와의 호환성 고려.

[N] 프리사인드: 비공개 객체 접근 임시 URL.
[O] 문서화된 제약: minutes 범위 명시.
[P] Bean Validation: 범위 벗어나면 400 → GlobalExceptionHandler로 형식화.

[Q] 교체: 기존 메타를 새 업로드 값으로 갱신.
[R] 삭제 설명: 코드상 S3 삭제 + DB 삭제(소프트/하드 중 실제 구현에 맞게 문서화).
[S] 204 No Content: 삭제 성공 시 바디 없이 응답.

[T] byRef 삭제: (refType, refId) 묶음 전부 삭제. 서비스에서 owner 검증 후 일괄 삭제.
────────────────────────────────────────────────────────────────────────── */
