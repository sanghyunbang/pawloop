package com.heattrip.heat_trip_backend.explore.web;

import com.heattrip.heat_trip_backend.explore.dto.CursorPageResponse;
import com.heattrip.heat_trip_backend.explore.dto.PageResponse;
import com.heattrip.heat_trip_backend.explore.dto.PlaceDetailDto;
import com.heattrip.heat_trip_backend.explore.dto.PlaceSearchCond;
import com.heattrip.heat_trip_backend.explore.dto.PlaceSummaryDto;

import com.heattrip.heat_trip_backend.explore.dto.PlaceFeaturesDto;
import com.heattrip.heat_trip_backend.explore.dto.EmotionalReviewDto;
import com.heattrip.heat_trip_backend.explore.dto.FeedbackRequestDto;
import com.heattrip.heat_trip_backend.explore.dto.FeedbackResponseDto;

import com.heattrip.heat_trip_backend.explore.service.ExploreEmotionService;
import com.heattrip.heat_trip_backend.explore.service.ExploreService;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.ArraySchema;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.Valid;

import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.stream.Stream;

/**
 * Explore 도메인의 REST 컨트롤러.
 *
 * <p>Base path: {@code /api/explore/places}</p>
 *
 * <p>엔드포인트 구성:</p>
 * <ul>
 *   <li>{@code GET /api/explore/places} - Offset(번호 기반) 페이지네이션 목록</li>
 *   <li>{@code GET /api/explore/places/scroll} - Cursor(무한 스크롤) 페이지네이션 목록</li>
 *   <li>{@code GET /api/explore/places/{id}} - 단건 상세 조회. 숫자 ID만 허용합니다.</li>
 *   <li>{@code GET /api/explore/places/{contentId}/features} - 공간 특성 조회</li>
 *   <li>{@code GET /api/explore/places/{contentId}/emotional-reviews} - 감정 리뷰 목록 조회</li>
 *   <li>{@code POST /api/explore/places/{contentId}/feedback} - 피드백 제출</li>
 * </ul>
 *
 * <p>이 컨트롤러는 입력 파라미터 파싱과 검증, 서비스 호출, DTO 또는
 * {@link ResponseEntity} 반환에 집중합니다.</p>
 *
 * @see ExploreService
 * @see ExploreEmotionService
 */
@Tag(name = "Explore", description = "Explore 도메인의 장소 탐색 REST API")
@RestController
@RequestMapping("/api/explore/places")
@Validated
public class ExploreController {

    private static final Logger log = LoggerFactory.getLogger(ExploreController.class);

    private final ExploreService service;
    private final ExploreEmotionService emotionService;

    /**
     * Explore REST 컨트롤러를 생성합니다.
     *
     * @param service 장소 탐색 서비스
     * @param emotionService 장소 감정/공간 특성 서비스
     */
    public ExploreController(ExploreService service, ExploreEmotionService emotionService) {
        this.service = service;
        this.emotionService = emotionService;
    }

    /**
     * 숫자 ID로 장소 상세 정보를 조회합니다.
     *
     * <p>{@code /scroll}, {@code /search} 같은 고정 경로와 충돌하지 않도록
     * 경로 변수에는 숫자만 허용합니다.</p>
     *
     * @param id 장소 ID
     * @return 장소 상세 DTO
     */
    @Operation(
        summary = "장소 상세 조회",
        description = "숫자 ID로 단건 장소 상세 정보를 조회합니다. /scroll 경로와 충돌하지 않도록 숫자 ID만 허용합니다."
    )
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "OK",
            content = @Content(schema = @Schema(implementation = PlaceDetailDto.class))),
        @ApiResponse(responseCode = "400", description = "Bad request"),
        @ApiResponse(responseCode = "404", description = "Place not found")
    })
    @GetMapping("/{id:\\d+}")
    public PlaceDetailDto get(
        @Parameter(description = "장소 ID", required = true)
        @PathVariable("id") Long id
    ) {
        return service.get(id);
    }

    /**
     * Offset(번호 기반) 페이지네이션으로 장소 목록을 조회합니다.
     *
     * @param areacode 지역 코드
     * @param sigungucode 시군구 코드
     * @param cat1 대분류 카테고리 코드
     * @param cat2 중분류 카테고리 코드
     * @param cat3 소분류 카테고리 코드
     * @param page 페이지 번호. {@code 0}부터 시작합니다.
     * @param size 페이지 크기. {@code 1} 이상 {@code 100} 이하입니다.
     * @return 페이지네이션된 장소 요약 목록
     */
    @Operation(
        summary = "장소 목록 조회",
        description = "Offset(번호 기반) 페이지네이션으로 장소 목록을 조회합니다."
    )
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "OK",
            content = @Content(schema = @Schema(implementation = PageResponse.class))),
        @ApiResponse(responseCode = "400", description = "Bad request")
    })
    @GetMapping
    public PageResponse<PlaceSummaryDto> list(
        @Parameter(description = "지역 코드")
        @RequestParam(name = "areacode",    required = false) Integer areacode,
        @Parameter(description = "시군구 코드")
        @RequestParam(name = "sigungucode", required = false) Integer sigungucode,
        @Parameter(description = "대분류 카테고리 코드")
        @RequestParam(name = "cat1",        required = false) String  cat1,
        @Parameter(description = "중분류 카테고리 코드")
        @RequestParam(name = "cat2",        required = false) String  cat2,
        @Parameter(description = "소분류 카테고리 코드")
        @RequestParam(name = "cat3",        required = false) String  cat3,
        @Parameter(description = "페이지 번호(0부터 시작)")
        @RequestParam(name = "page",        defaultValue = "0")  @Min(0)        int page,
        @Parameter(description = "페이지 크기(1~100)")
        @RequestParam(name = "size",        defaultValue = "20") @Min(1) @Max(100) int size
    ) {
        log.info("[GET] /api/explore/places?page={}&size={}&area={}&sigungu={}&cat1={}&cat2={}&cat3={}",
                 page, size, areacode, sigungucode, cat1, cat2, cat3);

        var cond = PlaceSearchCond.builder()
            .areacode(areacode)
            .sigungucode(sigungucode)
            .cat1(cat1)
            .cat2(cat2)
            .cat3(cat3)
            .build();

        return service.list(cond, page, size);
    }

    /**
     * Cursor(무한 스크롤) 페이지네이션으로 장소 목록을 조회합니다.
     *
     * <p>{@code cat3} 요청 파라미터는 CSV 문자열로 받고, 서비스 계층에서
     * 필요한 검색 조건으로 처리합니다.</p>
     *
     * @param areacode 지역 코드
     * @param sigungucode 시군구 코드
     * @param cat1 대분류 카테고리 코드
     * @param cat2 중분류 카테고리 코드
     * @param cat3Csv 소분류 카테고리 코드 CSV
     * @param cursor 다음 페이지 조회용 커서
     * @param size 조회 크기. {@code 1} 이상 {@code 100} 이하입니다.
     * @return 커서 기반 장소 요약 목록
     */
    @Operation(
        summary = "장소 무한 스크롤 조회",
        description = "Cursor(무한 스크롤) 페이지네이션으로 장소 목록을 조회합니다."
    )
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "OK",
            content = @Content(schema = @Schema(implementation = CursorPageResponse.class))),
        @ApiResponse(responseCode = "400", description = "Bad request")
    })
    @GetMapping("/scroll")
    public CursorPageResponse<PlaceSummaryDto> scroll(
        @Parameter(description = "지역 코드")
        @RequestParam(name = "areacode",    required = false) Integer areacode,
        @Parameter(description = "시군구 코드")
        @RequestParam(name = "sigungucode", required = false) Integer sigungucode,
        @Parameter(description = "대분류 카테고리 코드")
        @RequestParam(name = "cat1",        required = false) String  cat1,
        @Parameter(description = "중분류 카테고리 코드")
        @RequestParam(name = "cat2",        required = false) String  cat2,
        @Parameter(description = "소분류 카테고리 코드 CSV")
        @RequestParam(name = "cat3",        required = false) String  cat3Csv,
        @Parameter(description = "다음 페이지 조회용 커서")
        @RequestParam(name = "cursor",      required = false) String  cursor,
        @Parameter(description = "조회 크기(1~100)")
        @RequestParam(name = "size",        defaultValue = "20") @Min(1) @Max(100) int size
    ) {
        log.info("[GET] /api/explore/places/scroll?area={}&sigungu={}&cat1={}&cat2={}&cat3={}&cursor='{}'&size={}",
                 areacode, sigungucode, cat1, cat2, cat3Csv, cursor, size);

        var cond = PlaceSearchCond.builder()
            .areacode(areacode)
            .sigungucode(sigungucode)
            .cat1(cat1)
            .cat2(cat2)
            .cat3(cat3Csv)
            .build();

        try {
            return service.scroll(cond, cursor, size);
        } catch (Exception e) {
            log.error("scroll() failed: area={} sigungu={} cat1={} cat2={} cat3={} cursor='{}' size={}",
                      areacode, sigungucode, cat1, cat2, cat3Csv, cursor, size, e);
            throw e;
        }
    }

    /**
     * contentId 기준으로 장소 공간 특성을 조회합니다.
     *
     * <p>예: {@code GET /api/explore/places/3386455/features?includeConf=true}</p>
     *
     * <p>{@code includeConf=false}로 요청하면 {@code conf_*}, {@code n_reviews}
     * 같은 confidence 및 메타 필드를 제거하여 응답 payload를 가볍게 반환합니다.</p>
     *
     * @param contentId 관광 콘텐츠 ID
     * @param includeConf confidence 및 메타 필드 포함 여부
     * @return 공간 특성 DTO. 데이터가 없으면 {@code 404 Not Found}를 반환합니다.
     */
    @Operation(
        summary = "장소 공간 특성 조회",
        description = "contentId 기준으로 장소의 공간 특성을 조회합니다. includeConf=false이면 confidence/메타 필드를 응답에서 제외합니다."
    )
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "OK",
            content = @Content(schema = @Schema(implementation = PlaceFeaturesDto.class))),
        @ApiResponse(responseCode = "400", description = "Bad request"),
        @ApiResponse(responseCode = "404", description = "Features not found")
    })
    @GetMapping("/{contentId:\\d+}/features")
    public ResponseEntity<PlaceFeaturesDto> getPlaceFeatures(
        @Parameter(description = "관광 콘텐츠 ID", required = true)
        @PathVariable(name = "contentId") @Min(1) Long contentId,
        @Parameter(description = "confidence/메타 필드 포함 여부")
        @RequestParam(name = "includeConf", defaultValue = "true") boolean includeConf
    ) {
        PlaceFeaturesDto dto = emotionService.getFeatures(contentId);
        if (dto == null) return ResponseEntity.notFound().build();

        if (!includeConf) {
            dto.setN_reviews(null);
            dto.setN_blogs(null);
            dto.setConf_sociality(null);
            dto.setConf_spirituality(null);
            dto.setConf_adventure(null);
            dto.setConf_culture(null);
            dto.setConf_nature_healing(null);
            dto.setConf_quiet(null);
            dto.setMethod_ver(null);
            dto.setUpdated_at(null);
        }
        return ResponseEntity.ok(dto);
    }

    /**
     * contentId 기준으로 장소 감정 리뷰 목록을 조회합니다.
     *
     * <p>예: {@code GET /api/explore/places/3386455/emotional-reviews}</p>
     *
     * <p>현재는 전체 목록을 반환합니다. 필요하면 {@code page}, {@code size}
     * 파라미터를 추가하여 페이징 방식으로 확장할 수 있습니다.</p>
     *
     * @param contentId 관광 콘텐츠 ID
     * @return 감정 리뷰 목록
     */
    @Operation(
        summary = "장소 감정 리뷰 목록 조회",
        description = "contentId 기준으로 장소의 감정 리뷰 목록을 조회합니다."
    )
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "OK",
            content = @Content(array = @ArraySchema(schema = @Schema(implementation = EmotionalReviewDto.class)))),
        @ApiResponse(responseCode = "400", description = "Bad request")
    })
    @GetMapping("/{contentId:\\d+}/emotional-reviews")
    public ResponseEntity<List<EmotionalReviewDto>> getEmotionalReviews(
        @Parameter(description = "관광 콘텐츠 ID", required = true)
        @PathVariable(name = "contentId") @Min(1) Long contentId
    ) {
        List<EmotionalReviewDto> list = emotionService.getReviews(contentId);
        return ResponseEntity.ok(list);
    }

    /**
     * contentId 기준으로 사용자의 장소 피드백을 제출합니다.
     *
     * <p>예: {@code POST /api/explore/places/3386455/feedback}</p>
     *
     * <p>요청 본문 예:</p>
     * <pre>{@code
     * {
     *   "beforeEmotion": "SAD",
     *   "afterEmotion": "PROUD",
     *   "featureRatings": {
     *     "sociality": 0.4,
     *     "spirituality": 0.8
     *   },
     *   "content": "혼자였지만 힐링됐어요",
     *   "timestamp": "2025-09-08T14:22:00"
     * }
     * }</pre>
     *
     * @param contentId 관광 콘텐츠 ID
     * @param request 피드백 요청 DTO
     * @return 생성된 피드백 응답 DTO
     */
    @Operation(
        summary = "장소 피드백 제출",
        description = "contentId 기준으로 사용자의 감정 변화와 공간 특성 평가 피드백을 제출합니다."
    )
    @ApiResponses({
        @ApiResponse(responseCode = "201", description = "Created",
            content = @Content(schema = @Schema(implementation = FeedbackResponseDto.class))),
        @ApiResponse(responseCode = "400", description = "Bad request")
    })
    @PostMapping("/{contentId:\\d+}/feedback")
    public ResponseEntity<FeedbackResponseDto> postFeedback(
        @Parameter(description = "관광 콘텐츠 ID", required = true)
        @PathVariable(name = "contentId") @Min(1) Long contentId,
        @Valid @RequestBody FeedbackRequestDto request
    ) {
        FeedbackResponseDto res = emotionService.submitFeedback(contentId, request);
        return ResponseEntity.status(201).body(res);
    }

    /**
     * 검색어와 필터 조건으로 장소를 검색합니다.
     *
     * <p>{@code cat3}는 CSV 문자열로 요청받아 리스트로 변환한 뒤 검색 조건에 전달합니다.</p>
     *
     * @param q 검색어
     * @param contentTypeId 콘텐츠 타입 ID
     * @param cat3 소분류 카테고리 코드 CSV
     * @param emotionCategoryId 감정 카테고리 ID
     * @param page 페이지 번호
     * @param size 페이지 크기
     * @param sort 정렬 조건
     * @return 페이지네이션된 장소 요약 목록
     */
    @Operation(
        summary = "장소 고급 검색",
        description = "검색어, 콘텐츠 타입, cat3 CSV, 감정 카테고리, 정렬 조건으로 장소를 검색합니다."
    )
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "OK",
            content = @Content(schema = @Schema(implementation = PageResponse.class))),
        @ApiResponse(responseCode = "400", description = "Bad request")
    })
    @GetMapping("/search")
    public PageResponse<PlaceSummaryDto> search(
            @Parameter(description = "검색어")
            @RequestParam(name = "q", required = false) String q,
            @Parameter(description = "콘텐츠 타입 ID")
            @RequestParam(name = "contentTypeId", required = false) Integer contentTypeId,
            @Parameter(description = "소분류 카테고리 코드 CSV")
            @RequestParam(name = "cat3", required = false) String cat3,           // CSV
            @Parameter(description = "감정 카테고리 ID")
            @RequestParam(name = "emotionCategoryId", required = false) Integer emotionCategoryId,
            @Parameter(description = "페이지 번호")
            @RequestParam(name = "page", defaultValue = "0") Integer page,
            @Parameter(description = "페이지 크기")
            @RequestParam(name = "size", defaultValue = "20") Integer size,
            @Parameter(description = "정렬 조건")
            @RequestParam(name = "sort", required = false) String sort
    ) {
        List<String> cat3list = (cat3 == null || cat3.isBlank())
            ? List.of()
            : Stream.of(cat3.split(","))
                    .map(String::trim)
                    .filter(s -> !s.isEmpty())
                    .toList(); // Java 16 미만이면 .collect(Collectors.toList())

        var cond = new com.heattrip.heat_trip_backend.explore.dto.search.PlaceSearchCond(
                q, contentTypeId, cat3list, emotionCategoryId, page, size, sort
        );
        return service.searchAdvanced(cond);
    }
}
