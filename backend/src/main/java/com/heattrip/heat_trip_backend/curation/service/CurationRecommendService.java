package com.heattrip.heat_trip_backend.curation.service;

import com.heattrip.heat_trip_backend.curation.dto.LlmRecommendRequest;
import com.heattrip.heat_trip_backend.curation.dto.LlmRecommendResponse;
import com.heattrip.heat_trip_backend.curation.dto.PlaceScoreDTO;
import com.heattrip.heat_trip_backend.curation.dto.RankRequest;
import com.heattrip.heat_trip_backend.curation.dto.RecommendResultDto;
import com.heattrip.heat_trip_backend.curation.mood.MoodPadPreset;
import com.heattrip.heat_trip_backend.curation.port.RecommendationPort;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Objects;
import java.util.Set;
import java.util.stream.Stream;

@Slf4j
@Service
@RequiredArgsConstructor
public class CurationRecommendService {

    // 추천 생성은 외부 구현체에 직접 의존하지 않고 port를 통해 위임한다.
    private final RecommendationPort recommender;
    private final Cat3DictionaryService cat3Dict;
    private final ScoringService scoring;

    public RecommendResultDto recommend(RankRequest in) {

        // 이미 CAT3 필터가 있으면 LLM 단계를 건너뛰고 바로 내부 랭킹을 수행한다.
        if (in.getCat3Filter() != null && !in.getCat3Filter().isEmpty()) {
            log.info("Skip LLM: client provided cat3Filter(size={})", in.getCat3Filter().size());
            List<PlaceScoreDTO> ranked = scoring.rank(in);
            return new RecommendResultDto(ranked, null, null);
        }

        // 클라이언트가 명시한 PAD가 있으면 그대로 사용한다(하위 호환).
        // moodKey만 보내고 PAD가 비어있으면(null 또는 p/a/d 전부 0) 무드 프리셋으로 채운다.
        double pleasure = in.getPad() != null ? in.getPad().getPleasure() : 0.0;
        double arousal = in.getPad() != null ? in.getPad().getArousal() : 0.0;
        double dominance = in.getPad() != null ? in.getPad().getDominance() : 0.0;
        double energy = in.getEnergy();
        double social = in.getSocialNeed();

        if (in.getMoodKey() != null && MoodPadPreset.isZeroPad(in.getPad())) {
            MoodPadPreset.Preset preset = MoodPadPreset.find(in.getMoodKey());
            if (preset != null) {
                // intensity(1~5)로 PAD만 스케일하고 [-2,2]로 클램프한다.
                // 프리셋은 fractional double이므로 int PadDTO를 거치지 않고 직접 전달한다.
                double scale = MoodPadPreset.intensityScale(in.getIntensity());
                pleasure = MoodPadPreset.clampPad(preset.pleasure() * scale);
                arousal = MoodPadPreset.clampPad(preset.arousal() * scale);
                dominance = MoodPadPreset.clampPad(preset.dominance() * scale);
                // energy/social은 intensity 스케일 대상이 아니다.
                energy = preset.energy();
                social = preset.social();
                log.info("Applied mood preset: moodKey={}, intensity={}, scale={}, " +
                                "pad=({},{},{}), energy={}, social={}",
                        in.getMoodKey(), in.getIntensity(), scale,
                        pleasure, arousal, dominance, energy, social);
            } else {
                log.debug("No mood preset found for moodKey={}, leaving values as-is", in.getMoodKey());
            }
        }

        // 사용자 감정값(PAD)과 의도 정보를 외부 추천 요청 DTO로 변환한다.
        var llmReq = new LlmRecommendRequest(
                pleasure,
                arousal,
                dominance,
                energy,
                social,
                in.getMoodKey(),
                in.getPurposeKeywords(),
                in.getNotes()
        );

        // 추천 응답이 null이면 외부 추천 계약이 깨진 것으로 보고 즉시 실패시킨다.
        var res = Objects.requireNonNull(
                recommender.getRecommendation(llmReq),
                "Recommendation response must not be null"
        );

        // LLM이 반환한 카테고리 라벨을 내부 랭킹용 CAT3 코드로 변환한다.
        List<LlmRecommendResponse.CategoryGroup> categoryGroups =
                res.getCategoryGroups() == null ? List.of() : res.getCategoryGroups();

        var labels = categoryGroups.stream()
                .flatMap(group -> group.getCategories() == null
                        ? Stream.<String>empty()
                        : group.getCategories().stream())
                .toList();

        Set<String> cat3 = cat3Dict.resolveCat3Codes(labels);
        in.setCat3Filter(cat3.stream().toList());

        // 실제 관광지 점수 계산과 정렬은 기존 모놀리식의 도메인 로직에서 처리한다.
        List<PlaceScoreDTO> ranked = scoring.rank(in);

        // 클라이언트가 활용할 수 있도록 LLM 메타데이터를 응답에 그대로 포함한다.
        List<LlmRecommendResponse.Activity> activities =
                res.getActivities() == null ? List.of() : res.getActivities();

        var llmMeta = new RecommendResultDto.LlmMeta(
                res.getSchemaVersion(),
                res.getEmotionDiagnosis(),
                res.getThemeName(),
                res.getThemeDescription(),
                categoryGroups.stream()
                        .map(group -> new RecommendResultDto.LlmMeta.CategoryGroup(
                                group.getGroupName(),
                                group.getCategories()
                        ))
                        .toList(),
                activities.stream()
                        .map(activity -> new RecommendResultDto.LlmMeta.Activity(
                                activity.getTitle(),
                                activity.getDescription()
                        ))
                        .toList(),
                res.getKeywords(),
                res.getComfortLetter()
        );

        // 최종 응답은 추천 메타데이터와 랭킹 결과를 함께 반환한다.
        return new RecommendResultDto(ranked, llmMeta, in.getCat3Filter());
    }
}
