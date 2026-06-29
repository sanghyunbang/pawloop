package com.heattrip.heat_trip_backend.curation.mood;

import com.heattrip.heat_trip_backend.curation.dto.PadDTO;

import java.util.Map;
import java.util.Set;

/**
 * 무드(감정) → PAD/energy/social 프리셋 테이블.
 *
 * <p>3개 레포(Flutter / Spring / Python)가 공유하는 단일 진실 공급원(SSOT)이며,
 * 값의 출처는 프로젝트 docs/07-implementation-plan.md 4-1 절이다.</p>
 *
 * <p>스케일 주의: 프리셋 PAD 값은 -1..1 범위이지만 Python /recommend 서비스는
 * PAD를 [-2,2] 범위로 받으므로 그대로 전달한다(2를 곱하지 않는다).
 * energy/social은 [-1,1] 범위로 그대로 유효하다.</p>
 */
public final class MoodPadPreset {

    /** PAD + energy + social 프리셋 한 묶음. 값은 fractional double로 보존한다. */
    public record Preset(double pleasure, double arousal, double dominance,
                         double energy, double social) {
    }

    /** 한국어 moodKey로 키잉된 6개 무드 프리셋 테이블. */
    private static final Map<String, Preset> TABLE = Map.of(
            "기쁨", new Preset(0.6, 0.4, 0.3, 0.3, 0.3),   // joy
            "슬픔", new Preset(-0.5, -0.3, -0.2, -0.4, -0.3), // sadness
            "불안", new Preset(-0.3, 0.5, -0.4, 0.0, -0.2),  // anxiety
            "분노", new Preset(-0.4, 0.6, 0.3, 0.4, -0.1),   // anger
            "평온", new Preset(0.4, -0.4, 0.2, -0.3, 0.0),   // calm
            "설렘", new Preset(0.6, 0.6, 0.2, 0.5, 0.3)      // excitement
    );

    /**
     * SSOT 6개 한국어 무드 키 집합(기쁨/슬픔/불안/분노/평온/설렘).
     * UGC 감정 집계 등에서 유효 무드 라벨 판별에 사용한다.
     */
    public static final Set<String> MOOD_KEYS = TABLE.keySet();

    private MoodPadPreset() {
    }

    /**
     * moodKey에 해당하는 프리셋을 반환한다. 없으면 null.
     */
    public static Preset find(String moodKey) {
        if (moodKey == null) {
            return null;
        }
        return TABLE.get(moodKey);
    }

    /**
     * PAD가 비어있는지(프리셋으로 채워야 하는지) 판단한다.
     * pad가 null이거나 p/a/d가 모두 0이면 true.
     */
    public static boolean isZeroPad(PadDTO pad) {
        if (pad == null) {
            return true;
        }
        return pad.getPleasure() == 0 && pad.getArousal() == 0 && pad.getDominance() == 0;
    }

    /**
     * intensity(1~5)로부터 PAD 스케일 계수를 계산한다.
     * null이면 3(중립)으로 간주하여 1.0을 반환한다.
     */
    public static double intensityScale(Integer intensity) {
        int i = (intensity == null) ? 3 : intensity;
        return i / 3.0;
    }

    /** 값을 [-2,2]로 클램프한다. */
    public static double clampPad(double v) {
        if (v < -2.0) {
            return -2.0;
        }
        if (v > 2.0) {
            return 2.0;
        }
        return v;
    }
}
