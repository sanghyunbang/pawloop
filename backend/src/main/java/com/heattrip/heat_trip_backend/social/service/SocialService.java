package com.heattrip.heat_trip_backend.social.service;

import com.heattrip.heat_trip_backend.social.dto.CardDto;
import com.heattrip.heat_trip_backend.social.dto.CommentDto;
import com.heattrip.heat_trip_backend.social.entity.CardComment;
import com.heattrip.heat_trip_backend.social.entity.CardReaction;
import com.heattrip.heat_trip_backend.social.entity.EmotionCard;
import com.heattrip.heat_trip_backend.social.repository.CardCommentRepository;
import com.heattrip.heat_trip_backend.social.repository.CardReactionRepository;
import com.heattrip.heat_trip_backend.social.repository.EmotionCardRepository;

import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;

@Service
@Transactional(readOnly = true)
public class SocialService {

    /** 6개 무드 SSOT 한국어 키. */
    private static final Set<String> VALID_MOODS = Set.of("기쁨", "슬픔", "불안", "분노", "평온", "설렘");

    /** 허용 리액션 타입. */
    private static final List<String> REACTION_TYPES = List.of("SAME", "CHEER", "CALM");
    private static final Set<String> VALID_REACTIONS = Set.copyOf(REACTION_TYPES);

    private static final int MAX_BODY_LEN = 280;
    private static final int DEFAULT_LIMIT = 50;
    private static final int MAX_LIMIT = 100;

    private final EmotionCardRepository cardRepo;
    private final CardReactionRepository reactionRepo;
    private final CardCommentRepository commentRepo;

    public SocialService(EmotionCardRepository cardRepo,
                         CardReactionRepository reactionRepo,
                         CardCommentRepository commentRepo) {
        this.cardRepo = cardRepo;
        this.reactionRepo = reactionRepo;
        this.commentRepo = commentRepo;
    }

    /** 카드 공유. */
    @Transactional
    public EmotionCard share(Long userId, String handle, String moodKey, String body,
                             String placeName, Long placeId) {
        if (!VALID_MOODS.contains(moodKey)) {
            throw new IllegalArgumentException("Invalid moodKey: " + moodKey);
        }
        if (body == null || body.isBlank()) {
            throw new IllegalArgumentException("body is required");
        }
        String trimmed = body.trim();
        if (trimmed.length() > MAX_BODY_LEN) {
            throw new IllegalArgumentException("body too long (max " + MAX_BODY_LEN + ")");
        }

        String normalizedHandle = (handle == null || handle.isBlank()) ? null : handle.trim();
        // 개인정보 보호: 공유 시점에 동/구 단위로 흐려서 저장(정밀 위치는 절대 저장하지 않음).
        String coarsenedPlace = coarsenLocation(placeName, placeId);

        EmotionCard card = EmotionCard.builder()
                .userId(userId)
                .handle(normalizedHandle)
                .moodKey(moodKey)
                .body(trimmed)
                .placeName(coarsenedPlace)
                .placeId(placeId)
                .build();

        return cardRepo.save(card);
    }

    /** 단일 카드 → DTO (방금 공유한 카드 응답용). 리액션 카운트는 0, myReactions는 비어 있음. */
    public CardDto toDto(EmotionCard card, Long currentUserId) {
        List<CardReaction> reactions = reactionRepo.findByCardId(card.getId());
        Map<String, Integer> counts = emptyCounts();
        List<String> mine = new ArrayList<>();
        for (CardReaction r : reactions) {
            counts.merge(r.getReactionType(), 1, Integer::sum);
            if (currentUserId != null && currentUserId.equals(r.getUserId())) {
                mine.add(r.getReactionType());
            }
        }
        int commentCount = (int) commentRepo.countByCardId(card.getId());
        return mapCard(card, counts, mine, commentCount);
    }

    /** 최신순 피드. 페이지 내 카드들의 리액션을 한 번에 로드(N+1 방지). */
    public List<CardDto> feed(Long currentUserId, Integer limit) {
        int size = (limit == null || limit <= 0) ? DEFAULT_LIMIT : Math.min(limit, MAX_LIMIT);

        List<EmotionCard> cards = cardRepo.findAllByOrderByIdDesc(PageRequest.of(0, size));
        if (cards.isEmpty()) {
            return List.of();
        }

        List<Long> cardIds = new ArrayList<>(cards.size());
        for (EmotionCard c : cards) {
            cardIds.add(c.getId());
        }

        // 카드별 카운트 맵 + 카드별 내 리액션 집합을 단일 쿼리 결과에서 구성한다.
        Map<Long, Map<String, Integer>> countsByCard = new HashMap<>();
        Map<Long, List<String>> myByCard = new HashMap<>();
        for (CardReaction r : reactionRepo.findByCardIdIn(cardIds)) {
            countsByCard
                    .computeIfAbsent(r.getCardId(), k -> emptyCounts())
                    .merge(r.getReactionType(), 1, Integer::sum);
            if (currentUserId != null && currentUserId.equals(r.getUserId())) {
                myByCard.computeIfAbsent(r.getCardId(), k -> new ArrayList<>()).add(r.getReactionType());
            }
        }

        // 카드별 댓글 수를 단일 쿼리로 집계(N+1 방지).
        Map<Long, Integer> commentCountByCard = new HashMap<>();
        for (Object[] row : commentRepo.countByCardIdInGroupBy(cardIds)) {
            Long cardId = (Long) row[0];
            int cnt = ((Number) row[1]).intValue();
            commentCountByCard.put(cardId, cnt);
        }

        List<CardDto> out = new ArrayList<>(cards.size());
        for (EmotionCard c : cards) {
            Map<String, Integer> counts = countsByCard.getOrDefault(c.getId(), emptyCounts());
            List<String> mine = myByCard.getOrDefault(c.getId(), List.of());
            int commentCount = commentCountByCard.getOrDefault(c.getId(), 0);
            out.add(mapCard(c, counts, mine, commentCount));
        }
        return out;
    }

    /**
     * 리액션 토글. (cardId, userId, type)이 있으면 삭제(언리액션), 없으면 추가.
     * 반환: 해당 카드의 갱신된 {reactions, myReactions}.
     */
    @Transactional
    public Map<String, Object> toggleReaction(Long cardId, Long userId, String type) {
        if (type == null || !VALID_REACTIONS.contains(type)) {
            throw new IllegalArgumentException("Invalid reaction type: " + type);
        }
        if (!cardRepo.existsById(cardId)) {
            throw new IllegalArgumentException("Card not found: " + cardId);
        }

        reactionRepo.findByCardIdAndUserIdAndReactionType(cardId, userId, type)
                .ifPresentOrElse(
                        reactionRepo::delete,
                        () -> reactionRepo.save(CardReaction.builder()
                                .cardId(cardId)
                                .userId(userId)
                                .reactionType(type)
                                .build())
                );

        // 토글 후 최신 상태로 재계산.
        Map<String, Integer> counts = emptyCounts();
        List<String> mine = new ArrayList<>();
        for (CardReaction r : reactionRepo.findByCardId(cardId)) {
            counts.merge(r.getReactionType(), 1, Integer::sum);
            if (userId.equals(r.getUserId())) {
                mine.add(r.getReactionType());
            }
        }

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("reactions", counts);
        result.put("myReactions", mine);
        return result;
    }

    // ───────────────────────── comments ─────────────────────────

    /** 댓글 작성. body 비어있지 않고 ≤280자, 카드 존재 검증. */
    @Transactional
    public CommentDto addComment(Long cardId, Long userId, String handle, String body) {
        if (!cardRepo.existsById(cardId)) {
            throw new IllegalArgumentException("Card not found: " + cardId);
        }
        if (body == null || body.isBlank()) {
            throw new IllegalArgumentException("body is required");
        }
        String trimmed = body.trim();
        if (trimmed.length() > MAX_BODY_LEN) {
            throw new IllegalArgumentException("body too long (max " + MAX_BODY_LEN + ")");
        }
        String normalizedHandle = (handle == null || handle.isBlank()) ? null : handle.trim();

        CardComment saved = commentRepo.save(CardComment.builder()
                .cardId(cardId)
                .userId(userId)
                .handle(normalizedHandle)
                .body(trimmed)
                .build());

        return mapComment(saved);
    }

    /** 단일 카드의 댓글 목록(오래된 순). */
    public List<CommentDto> comments(Long cardId) {
        List<CommentDto> out = new ArrayList<>();
        for (CardComment c : commentRepo.findByCardIdOrderByIdAsc(cardId)) {
            out.add(mapComment(c));
        }
        return out;
    }

    // ───────────────────────── helpers ─────────────────────────

    private static Map<String, Integer> emptyCounts() {
        Map<String, Integer> m = new LinkedHashMap<>();
        for (String t : REACTION_TYPES) {
            m.put(t, 0);
        }
        return m;
    }

    private static CardDto mapCard(EmotionCard c, Map<String, Integer> counts, List<String> mine, int commentCount) {
        return new CardDto(
                c.getId(),
                c.getHandle(),
                c.getMoodKey(),
                c.getPlaceName(),
                c.getBody(),
                c.getCreatedAt() == null ? null : c.getCreatedAt().format(DateTimeFormatter.ISO_LOCAL_DATE_TIME),
                counts,
                mine,
                commentCount
        );
    }

    private static CommentDto mapComment(CardComment c) {
        return new CommentDto(
                c.getId(),
                c.getHandle(),
                c.getBody(),
                c.getCreatedAt() == null ? null : c.getCreatedAt().format(DateTimeFormatter.ISO_LOCAL_DATE_TIME)
        );
    }

    // ─────────────────────── location coarsening ───────────────────────

    /** 한 토큰 끝이 행정구역 접미사인지 검사하기 위한 패턴들. */
    private static final Pattern DONG_TOKEN = Pattern.compile(".+(동|읍|면|리)([0-9]+가)?$");
    private static final Pattern GU_TOKEN = Pattern.compile(".+(구|군)$");
    private static final Pattern SI_DO_TOKEN = Pattern.compile(".+(시|도)$");

    /**
     * 정밀 위치를 동/구 단위로 흐린다(개인정보 보호).
     * 외부 의존성 없이 placeName 을 정규식으로 코어슨한다.
     * - 동/읍/면/리 로 끝나는 토큰이 있으면 그 토큰(과 가능하면 앞선 구/군 토큰)을 반환.
     * - 없으면 구/군 토큰을, 그것도 없으면 시/도 토큰을 반환.
     * - 행정구역 토큰이 전혀 없으면 원본 placeName 을 그대로 반환(임의 위치를 만들지 않음).
     * placeName 이 null/blank 면 null 반환.
     *
     * placeId 는 시그니처에 포함되나, 이 저장소에는 좌표→행정동 역지오코딩 메서드가
     * 없으므로(KakaoLocalClient 는 키워드 검색만 제공) 사용하지 않는다.
     */
    static String coarsenLocation(String placeName, Long placeId) {
        if (placeName == null || placeName.isBlank()) {
            return null;
        }
        String trimmed = placeName.trim();
        String[] tokens = trimmed.split("\\s+");

        // 1) 동/읍/면/리 토큰 우선.
        for (int i = 0; i < tokens.length; i++) {
            if (DONG_TOKEN.matcher(tokens[i]).matches()) {
                // 가능하면 앞선 구/군 토큰을 붙여 맥락을 남긴다.
                if (i > 0 && GU_TOKEN.matcher(tokens[i - 1]).matches()) {
                    return tokens[i - 1] + " " + tokens[i];
                }
                return tokens[i];
            }
        }
        // 2) 구/군 토큰.
        for (String token : tokens) {
            if (GU_TOKEN.matcher(token).matches()) {
                return token;
            }
        }
        // 3) 시/도 토큰.
        for (String token : tokens) {
            if (SI_DO_TOKEN.matcher(token).matches()) {
                return token;
            }
        }
        // 4) 행정구역 토큰 없음 → 원본 유지(짧은 지역명/공공 POI일 가능성).
        return trimmed;
    }
}
