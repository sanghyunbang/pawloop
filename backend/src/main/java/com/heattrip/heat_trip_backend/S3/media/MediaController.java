package com.heattrip.heat_trip_backend.S3.media;

import com.heattrip.heat_trip_backend.S3.UploadCategory;
import com.heattrip.heat_trip_backend.S3.media.dto.MediaItemResponse;
import com.heattrip.heat_trip_backend.S3.media.dto.UrlResponse;
import com.heattrip.heat_trip_backend.S3.media.dto.VideoTicketResponse;
import com.heattrip.heat_trip_backend.S3.media.dto.VideoUploadRequest;
import com.heattrip.heat_trip_backend.user.CurrentUser;
import com.heattrip.heat_trip_backend.error.GlobalExceptionHandler.ErrorResponse; // [①] 에러 스키마 참조
import com.heattrip.heat_trip_backend.user.entity.User;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.*;
import io.swagger.v3.oas.annotations.responses.*;
import io.swagger.v3.oas.annotations.tags.Tag;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;

import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
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
        description = "Uploads multiple files to S3 and returns stored metadata and public URLs. "
                + "Uploading is not attaching — the rows come back with no reference (#509).", // [C]
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
        // 401 은 Spring Security 의 HttpStatusEntryPoint 가 만들고 본문이 없다.
        // 계약(openapi.yaml components/responses/Unauthorized)도 본문 없음으로 확정돼 있다. (#5)
        @ApiResponse(responseCode = "401", description = "Unauthorized", content = @Content),
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
        // [G] refType·refId 를 여기서 안 받는다. 받아서 그대로 적으면 남의 글 id 를 실은
        // 사진이 그 글에 붙었다(#509) — 붙이기는 MediaAttachment.attach 한 길뿐이다.
        @Parameter(description = "Pixel width — only with a single file (#429)")
        @RequestParam(name = "width",  required = false) @Min(1) Integer width,
        @Parameter(description = "Pixel height — only with a single file (#429)")
        @RequestParam(name = "height", required = false) @Min(1) Integer height,
        @CurrentUser User me // [H] 인증 주체. 해석은 CurrentUserArgumentResolver 한 곳뿐이다 (이슈 #5)
    ) {
        // 영상은 이 문으로 안 들어온다 — api.pawloop.app 앞의 Cloudflare 가 100MB 에서 끊는다.
        // 서명 URL 로 S3 에 직접 올리는 경로가 따로 있다(#429). 여기서 막지 않으면 100MB 짜리
        // 본문이 서버 메모리를 지나다 터널에서 죽고, 사용자는 "네트워크 오류" 만 본다.
        if (category.isVideo()) {
            throw new IllegalArgumentException("영상은 이 경로로 올릴 수 없습니다. 서명 URL 로 올려 주세요.");
        }
        // 크기는 파일 하나에 하나다. 여러 장에 한 쌍을 주면 어느 장의 것인지 모른다.
        if ((width != null || height != null) && files.size() != 1) {
            throw new IllegalArgumentException("width·height 는 파일이 하나일 때만 줄 수 있습니다.");
        }
        if ((width == null) != (height == null)) {
            throw new IllegalArgumentException("width·height 는 함께 줘야 합니다.");
        }
        var saved = mediaService.uploadMany(files, category, me.getId().toString(),
                width, height); // [I] 업로드+저장
        return ResponseEntity.ok(saved.stream().map(this::toItem).toList()); // [K] 200 OK + DTO 리스트
    }

    /** [J] CDN 공개 URL 을 여기서 조립한다 — DTO 는 저장소를 모른다. */
    private MediaItemResponse toItem(MediaObject m) {
        return MediaItemResponse.of(
                m,
                mediaService.publicUrl(m.getObjectKey()),
                m.getPosterKey() == null ? null : mediaService.publicUrl(m.getPosterKey()));
    }

    // ─────────────────────────────────────────────────────────────────────
    // C: 영상 — 자리 잡기 · 끝내기 (#429). 파일은 앱이 S3 에 직접 올린다
    // ─────────────────────────────────────────────────────────────────────
    @Operation(
        summary = "Reserve a video slot — get a presigned PUT",
        description = "Videos never pass through this server (Cloudflare caps request bodies at 100MB). "
                + "Declare type/size/length, PUT the file to uploadUrl with the same Content-Type, then call complete.",
        security = { @SecurityRequirement(name = "bearerAuth") }
    )
    @ApiResponses({
        @ApiResponse(responseCode = "201", description = "Reserved — pending row and a 15-minute presigned PUT",
            content = @Content(mediaType = "application/json",
                schema = @Schema(implementation = VideoTicketResponse.class))),
        @ApiResponse(responseCode = "400", description = "Not mp4/mov, over 150MB, over 60 s, or width without height",
            content = @Content(mediaType = "application/json",
                schema = @Schema(implementation = ErrorResponse.class))),
        @ApiResponse(responseCode = "401", description = "Unauthorized", content = @Content)
    })
    @PostMapping(path = "/videos", consumes = MediaType.APPLICATION_JSON_VALUE, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<VideoTicketResponse> reserveVideo(
        @Valid @RequestBody VideoUploadRequest body,
        @CurrentUser User me
    ) {
        MediaService.VideoTicket ticket = mediaService.reserveVideo(
                me.getId().toString(), body.contentType(), body.size(),
                body.width(), body.height(), body.durationMs());
        return ResponseEntity.status(HttpStatus.CREATED).body(new VideoTicketResponse(
                ticket.media().getId(), ticket.media().getObjectKey(), ticket.uploadUrl().toString()));
    }

    @Operation(
        summary = "Finish a video upload — poster in, HEAD on S3, ready",
        description = "The server confirms the object is on S3 with the declared size, stores the poster and flips "
                + "the row to ready. Calling it again returns the same item without touching the poster.",
        security = { @SecurityRequirement(name = "bearerAuth") }
    )
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Ready",
            content = @Content(mediaType = "application/json",
                schema = @Schema(implementation = MediaItemResponse.class))),
        @ApiResponse(responseCode = "400", description = "Not a video, size differs from what was declared, or the poster is not an image",
            content = @Content(mediaType = "application/json",
                schema = @Schema(implementation = ErrorResponse.class))),
        @ApiResponse(responseCode = "401", description = "Unauthorized", content = @Content),
        @ApiResponse(responseCode = "404", description = "Not mine — same as not there",
            content = @Content(mediaType = "application/json",
                schema = @Schema(implementation = ErrorResponse.class))),
        @ApiResponse(responseCode = "409", description = "The file has not arrived on S3 yet — PUT it, then call again",
            content = @Content(mediaType = "application/json",
                schema = @Schema(implementation = ErrorResponse.class)))
    })
    @PostMapping(path = "/{mediaId}/complete",
                 consumes = MediaType.MULTIPART_FORM_DATA_VALUE,
                 produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<MediaItemResponse> completeVideo(
        @Parameter(description = "Media id from the ticket", required = true)
        @PathVariable(name = "mediaId") @Min(1) Long mediaId,
        @Parameter(description = "Poster (thumbnail) the app rendered — jpeg/png/webp")
        @RequestPart("poster") MultipartFile poster,
        @CurrentUser User me
    ) {
        return ResponseEntity.ok(toItem(mediaService.completeVideo(mediaId, poster, me.getId().toString())));
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
        description = "Issues a time-limited presigned URL for private delivery. "
                + "Only for a key you uploaded — anything else is 404.", // [N]
        security = { @SecurityRequirement(name = "bearerAuth") }
    )
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "OK",
            content = @Content(schema = @Schema(implementation = UrlResponse.class))),
        @ApiResponse(responseCode = "400", description = "Bad request",
            content = @Content(mediaType = "application/json",
                schema = @Schema(implementation = ErrorResponse.class))),
        // 401 은 Spring Security 의 HttpStatusEntryPoint 가 만들고 본문이 없다.
        // 계약(openapi.yaml components/responses/Unauthorized)도 본문 없음으로 확정돼 있다. (#5)
        @ApiResponse(responseCode = "401", description = "Unauthorized", content = @Content),
        @ApiResponse(responseCode = "404", description = "Media not found",
            content = @Content(mediaType = "application/json",
                schema = @Schema(implementation = ErrorResponse.class))),
        @ApiResponse(responseCode = "500", description = "Internal Server Error",
            content = @Content(mediaType = "application/json",
                schema = @Schema(implementation = ErrorResponse.class)))
    })
    @GetMapping(path = "/presigned", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<UrlResponse> getPresigned(
        @Parameter(description = "S3 object key — one you uploaded", required = true)
        @RequestParam(name = "key") String objectKey,
        @Parameter(description = "Expiration in minutes (1~120)") // [O] 제약 문서화
        @RequestParam(name = "minutes", defaultValue = "10") @Min(1) @Max(120) int minutes, // [P] Bean Validation
        @CurrentUser User me
    ) {
        // 서명은 서버 자격증명으로 한다 — 받은 키를 그대로 서명하면 인증만 있는 사람이
        // 버킷의 어떤 객체든 읽는다(#509). 키는 응답 DTO 와 CDN URL 로 이미 밖에 나가 있다.
        var url = mediaService.presignedUrl(objectKey, Duration.ofMinutes(minutes),
                me.getId().toString());
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
        // 401 은 Spring Security 의 HttpStatusEntryPoint 가 만들고 본문이 없다.
        // 계약(openapi.yaml components/responses/Unauthorized)도 본문 없음으로 확정돼 있다. (#5)
        @ApiResponse(responseCode = "401", description = "Unauthorized", content = @Content),
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
        @CurrentUser User me
    ) {
        var m = mediaService.replace(mediaId, file, me.getId().toString());
        return ResponseEntity.ok(toItem(m));
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
        // 401 은 Spring Security 의 HttpStatusEntryPoint 가 만들고 본문이 없다.
        // 계약(openapi.yaml components/responses/Unauthorized)도 본문 없음으로 확정돼 있다. (#5)
        @ApiResponse(responseCode = "401", description = "Unauthorized", content = @Content),
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
        @CurrentUser User me
    ) {
        mediaService.delete(mediaId, me.getId().toString());
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
        // 401 은 Spring Security 의 HttpStatusEntryPoint 가 만들고 본문이 없다.
        // 계약(openapi.yaml components/responses/Unauthorized)도 본문 없음으로 확정돼 있다. (#5)
        @ApiResponse(responseCode = "401", description = "Unauthorized", content = @Content),
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
        @CurrentUser User me
    ) {
        mediaService.deleteByRef(refType, refId, me.getId().toString());
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
[H] @CurrentUser: CurrentUserArgumentResolver 가 users.id 로 사용자 행을 로드해 주입한다(이슈 #5).
    예전에는 @AuthenticationPrincipal String 이었고, 필터의 principal 타입이 바뀌자 예외도 경고도
    컴파일 에러도 없이 **200 OK 인 채로 null 이 주입**됐다 — MediaService 의 소유권 검사 4곳이
    통째로 무력화되는 조용한 회귀다. AuthSubjectContractSpecTest 가 재도입을 막는다.
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
