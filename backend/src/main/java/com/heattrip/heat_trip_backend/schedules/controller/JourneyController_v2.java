package com.heattrip.heat_trip_backend.schedules.controller;

import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.server.ResponseStatusException;

import com.heattrip.heat_trip_backend.OAuth.principal.CurrentUser;
import com.heattrip.heat_trip_backend.S3.UploadCategory;
import com.heattrip.heat_trip_backend.S3.media.MediaObject;
import com.heattrip.heat_trip_backend.S3.media.MediaService;
import com.heattrip.heat_trip_backend.schedules.DTO.JourneyRequestDto;
import com.heattrip.heat_trip_backend.schedules.DTO.JourneyResponseDto;
import com.heattrip.heat_trip_backend.schedules.Service.JourneyService_v2;
import com.heattrip.heat_trip_backend.schedules.entity.Journey;
import com.heattrip.heat_trip_backend.user.entity.User;

import org.springframework.http.HttpStatus;

@RestController
@RequestMapping("/journeys/v2")
public class JourneyController_v2 {

    // ─────────────────────────────────────
    // 의존성
    // ─────────────────────────────────────
    private final JourneyService_v2 journeyService;
    private final MediaService mediaService;

    // 여정-미디어 연결에 사용할 refType 상수
    private static final String REF_TYPE = "JOURNEY";

    public JourneyController_v2(JourneyService_v2 journeyService,
                                MediaService mediaService) {
        this.journeyService = journeyService;
        this.mediaService = mediaService;
    }

    // ─────────────────────────────────────
    // 내부 유틸 (권한/소유 검증, DTO 변환)
    // ─────────────────────────────────────

    // 예전에는 여기 private User requireUser(HttpServletRequest) 가 있었다. 그 안의
    // ResponseStatusException(401) 은 실제로 401 이 아니라 **500** 으로 나가고 있었다(실측 확인) —
    // GlobalExceptionHandler 의 @ExceptionHandler(Exception.class) 가 먼저 잡기 때문이다.
    // 인증은 @CurrentUser 가 맡고 실패는 본문 없는 401 이다. (이슈 #5)
    //
    // 아래 requireOwnedJourney 의 404/403 은 그대로 둔다 — 인증이 아니라 존재·소유 검증이다.
    //
    // **그 둘은 이 PR 이후에도 500 으로 나간다.** 접근 자체는 막히므로 인가 구멍은 아니지만
    // 앱은 '없음/권한없음'과 '서버 장애'를 구분할 수 없고, 500 본문에 내부 메시지
    // (`404 NOT_FOUND "Journey not found"`)가 실린다. 고치려면 GlobalExceptionHandler 의
    // catch-all 보다 ResponseStatusException 을 먼저 잡아야 하고, 그건 전역 에러 계약과
    // NoResourceFoundException 처리까지 함께 건드리는 변경이라 #5 범위 밖이다.
    // 소유자: 이슈 #44 (GlobalExceptionHandler 가 ResponseStatusException 을 삼킨다).

    /** 여정 존재/소유자 검증(없으면 404, 소유 아니면 403) */
    private Journey requireOwnedJourney(Long id, User user) {
        Journey j = journeyService.findById(id).orElse(null);
        if (j == null) throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Journey not found");
        if (!j.getUser().getId().equals(user.getId()))
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Forbidden");
        return j;
    }

    /** 미디어를 뷰 DTO로 변환 */
    private record MediaView(Long id, String key, String url, String contentType, long size) {}
    private record JourneyWithImagesResponse(JourneyResponseDto journey, List<MediaView> images) {}

    private List<MediaView> toMediaViews(List<MediaObject> list) {
        return list.stream()
            .map(m -> new MediaView(
                m.getId(),
                m.getObjectKey(),
                mediaService.publicUrl(m.getObjectKey()), // 공개 배포 시 public URL, 비공개면 presignedUrl 사용
                m.getContentType(),
                m.getSize()
            ))
            .collect(Collectors.toList());
    }

    private JourneyWithImagesResponse composeJourneyWithImages(Journey j) {
        List<MediaObject> media = mediaService.findByRef(REF_TYPE, j.getId().toString());
        return new JourneyWithImagesResponse(new JourneyResponseDto(j), toMediaViews(media));
    }

    // ─────────────────────────────────────
    // R: 목록 조회 (이미지 포함)
    // ─────────────────────────────────────
    @GetMapping("/entries")
    public ResponseEntity<?> listMyJourneys(@CurrentUser User user) {
        System.out.println("        ㅡㅡㅡㅡㅡGet Entries 진입 ");
        List<Journey> journeys = journeyService.getJourneysByUser(user);

        List<JourneyWithImagesResponse> body = journeys.stream()
            .map(this::composeJourneyWithImages)
            .collect(Collectors.toList());

            System.out.println("ㅡㅡㅡㅡㅡㅡㅡentries에서 보내주고 있는 값 = "+body.get(0));

        return ResponseEntity.ok(body);
    }

    // ─────────────────────────────────────
    // R: 단건 조회 (이미지 포함)
    // ─────────────────────────────────────
    @GetMapping("/entries/{id}")
    public ResponseEntity<?> getJourney(@PathVariable Long id, @CurrentUser User user) {
        Journey j = requireOwnedJourney(id, user);
        return ResponseEntity.ok(composeJourneyWithImages(j));
    }

    // ─────────────────────────────────────
    // C: 여정 생성 (본문만)
    // ─────────────────────────────────────
    @PostMapping("/entries")
    public ResponseEntity<?> createJourney(@RequestBody JourneyRequestDto dto, @CurrentUser User user) {
        System.out.println("           ㅡㅡㅡㅡㅡㅡㅡentrys 진입완료 들어온 값 : \n" + dto);
        Journey saved = journeyService.saveJourney(dto, user);
        return ResponseEntity.ok(new JourneyWithImagesResponse(new JourneyResponseDto(saved), List.of()));
    }

    // ─────────────────────────────────────
    // C: 여정 + 이미지 동시 생성 (multipart: dto + images[])
    // ─────────────────────────────────────
    @PostMapping(path = "/entries/with-images", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<?> createJourneyWithImages(
        @RequestPart("dto") JourneyRequestDto dto,
        @RequestPart(value = "images", required = false) List<MultipartFile> images,
        @CurrentUser User user
    ) {
        Journey saved = journeyService.saveJourney(dto, user);

        if (images != null && !images.isEmpty()) {
            mediaService.uploadMany(
                images,
                UploadCategory.JOURNEY_IMAGE,
                user.getId().toString(),
                REF_TYPE,
                saved.getId().toString()
            );
        }
        return ResponseEntity.ok(composeJourneyWithImages(saved));
    }

    // ─────────────────────────────────────
    // U: 여정 본문 수정 (이미지 변경은 별도 엔드포인트)
    // ─────────────────────────────────────
    @PutMapping("/entries/{Did}")
    public ResponseEntity<?> updateJourney(
        @PathVariable("Did") Long id,
        @RequestBody JourneyRequestDto dto,
        @CurrentUser User user
    ) {
        System.out.println("    ㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡupdate diary 진입함. 진입한 게시물 id : " + id);
        Journey target = requireOwnedJourney(id, user);
        Journey updated = journeyService.updateJourney(target, dto);
        return ResponseEntity.ok(composeJourneyWithImages(updated));
    }

    // ─────────────────────────────────────
    // U: 기존 여정에 이미지 추가 (multipart: images[])
    // ─────────────────────────────────────
    @PostMapping(path = "/entries/{id}/images", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<?> addImages(
        @PathVariable Long id,
        @RequestPart("images") List<MultipartFile> images,
        @CurrentUser User user
    ) {
        Journey j = requireOwnedJourney(id, user);

        if (images == null || images.isEmpty())
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "No files provided");

        mediaService.uploadMany(
            images,
            UploadCategory.JOURNEY_IMAGE,
            user.getId().toString(),
            REF_TYPE,
            j.getId().toString()
        );

        return ResponseEntity.ok(composeJourneyWithImages(j));
    }

    // ─────────────────────────────────────
    // D(부분): 특정 이미지 단건 삭제
    //   - 연결 검증까지 하려면 MediaService.deleteForJourney 사용
    // ─────────────────────────────────────
    @DeleteMapping("/entries/{id}/images/{mediaId}")
    public ResponseEntity<?> deleteOneImage(
        @PathVariable Long id,
        @PathVariable Long mediaId,
        @CurrentUser User user
    ) {
        Journey j = requireOwnedJourney(id, user);

        // 연결 검증 버전 (권장)
        mediaService.deleteForJourney(mediaId, j.getId().toString(), user.getId().toString());

        return ResponseEntity.ok(composeJourneyWithImages(j));
    }

    // ─────────────────────────────────────
    // D: 여정 삭제 (연결 이미지 전체 삭제 후 본문 삭제)
    // ─────────────────────────────────────
    @DeleteMapping("/entries/{diaryId}")
    public ResponseEntity<?> deleteJourney(@PathVariable("diaryId") Long id, @CurrentUser User user) {
        System.out.println("    ㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡdelete diary 진입함. 진입한 게시글 id :  " + id );
        Journey j = requireOwnedJourney(id, user);

        // 1) 연결된 미디어 전체 삭제
        mediaService.deleteByRef(REF_TYPE, j.getId().toString(), user.getId().toString());

        // 2) 본문 삭제
        journeyService.deleteJourney(j);

        return ResponseEntity.noContent().build();
    }

    // ─────────────────────────────────────
    // 통계 (간단 예시)
    // ─────────────────────────────────────
    @GetMapping("/stats")
    public ResponseEntity<?> stats(@CurrentUser User user) {
        List<Journey> entries = journeyService.getJourneysByUser(user);
        Map<String, Object> stats = Map.of("entryCount", entries.size());
        return ResponseEntity.ok(stats);
    }
}
