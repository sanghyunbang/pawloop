package com.heattrip.heat_trip_backend.walk.ai;

import com.heattrip.heat_trip_backend.dog.DogProfileView;
import com.heattrip.heat_trip_backend.walk.dto.WalkStatsResponse;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.DayOfWeek;
import java.time.LocalDate;
import java.util.HexFormat;
import java.util.List;
import java.util.Locale;

/**
 * 모델에 주는 재료 — 이슈 #486. <b>1단계 통계가 만든 숫자와 아이의 크기 · 나이대뿐이다.</b>
 *
 * <p>여기 없는 것이 곧 보내지 않는 것이다: 이름 · 이메일 · 좌표 · 장소명 · 메모. 개인정보처리방침
 * v1.8 의 "AI 주간 요약" 항목이 이 목록을 그대로 적는다 — 이 파일을 넓히면 그 문서도 같이.
 *
 * <p>아이는 {@link DogProfileView}(dog 모듈의 공개 표면)로만 받는다 — {@code dog.entity} · {@code dog.dto}
 * 를 부르면 모듈 경계 위반이다(#97 · #98).
 *
 * @param weekStart   이번 주 월요일(KST)
 * @param today       오늘 요일 — "아직 남은 요일" 을 모델이 세게
 * @param totalKm     이번 주 거리
 * @param walkCount   이번 주 횟수
 * @param totalMinutes 이번 주 분
 * @param weekKm      월~일 거리
 * @param weekMinutes 월~일 분
 * @param lastWeekKm  지난주 거리
 * @param lastWeekCount 지난주 횟수
 * @param lastWeekMinutes 지난주 분
 * @param parts       시간대별(새벽 · 아침 · 낮 · 저녁) 횟수
 * @param dogSizeKey  아이 크기 {@code small} · {@code medium} · {@code large}(없으면 null)
 * @param dogAgeMonths 아이 나이(개월, 없으면 null)
 */
public record WeeklyInsightInput(
        LocalDate weekStart,
        DayOfWeek today,
        double totalKm,
        int walkCount,
        int totalMinutes,
        List<Double> weekKm,
        List<Integer> weekMinutes,
        double lastWeekKm,
        int lastWeekCount,
        int lastWeekMinutes,
        List<WalkStatsResponse.PartOfDayCount> parts,
        String dogSizeKey,
        Integer dogAgeMonths) {

    private static final String[] DAYS = {"월", "화", "수", "목", "금", "토", "일"};
    private static final String[] PART_LABELS = {"새벽", "아침", "낮", "저녁"};

    public static WeeklyInsightInput of(WalkStatsResponse stats, DogProfileView dog, LocalDate today) {
        int minutes = 0;
        for (Integer m : stats.weekMinutes()) {
            minutes += m;
        }
        return new WeeklyInsightInput(
                stats.weekStart(),
                today.getDayOfWeek(),
                stats.totalKm(),
                stats.walkCount(),
                minutes,
                stats.weekKm(),
                stats.weekMinutes(),
                stats.summary().lastWeekKm(),
                stats.summary().lastWeekCount(),
                stats.summary().lastWeekMinutes(),
                stats.summary().byPartOfDay(),
                dog == null ? null : dog.sizeKey(),
                dog == null ? null : dog.ageMonths());
    }

    /** 아이 크기별 하루 권장 분 — 앱의 {@code WalkGoal.recommendedFor} 와 같은 수(30 · 45 · 60). */
    public Integer recommendedMinutesPerDay() {
        if (dogSizeKey == null) {
            return null;
        }
        return switch (dogSizeKey) {
            case "medium" -> 45;
            case "large" -> 60;
            default -> 30;
        };
    }

    /**
     * 모델에 보내는 글 — 사람이 읽어도 그대로 이해되는 한국어 표. 숫자 검사의 "입력 집합" 도 이 글에서
     * 뽑는다: 여기 적힌 숫자만 출력에 나올 수 있다.
     */
    public String render() {
        StringBuilder b = new StringBuilder();
        b.append("이번 주(월요일 ").append(weekStart.getMonthValue()).append("월 ")
                .append(weekStart.getDayOfMonth()).append("일 시작, 오늘은 ")
                .append(DAYS[today.getValue() - 1]).append("요일)\n");
        b.append("- 이번 주 합계: ").append(km(totalKm)).append("km · ").append(walkCount)
                .append("회 · ").append(totalMinutes).append("분\n");
        b.append("- 요일별 km: ");
        for (int i = 0; i < 7 && i < weekKm.size(); i++) {
            if (i > 0) {
                b.append(", ");
            }
            b.append(DAYS[i]).append(' ').append(km(weekKm.get(i)));
        }
        b.append('\n');
        b.append("- 시간대별 횟수: ");
        for (int i = 0; i < parts.size(); i++) {
            if (i > 0) {
                b.append(", ");
            }
            String label = i < PART_LABELS.length ? PART_LABELS[i] : parts.get(i).part();
            b.append(label).append(' ').append(parts.get(i).count()).append("회");
        }
        b.append('\n');
        b.append("- 지난주: ").append(km(lastWeekKm)).append("km · ").append(lastWeekCount)
                .append("회 · ").append(lastWeekMinutes).append("분\n");
        if (dogSizeKey != null) {
            b.append("- 아이: ").append(sizeLabel(dogSizeKey));
            if (dogAgeMonths != null) {
                b.append(", ").append(ageLabel(dogAgeMonths));
            }
            b.append(", 하루 권장 ").append(recommendedMinutesPerDay()).append("분 안팎\n");
        }
        return b.toString();
    }

    /** 입력이 같으면 같은 해시 — 캐시의 열쇠. 입력이 바뀌면(새 산책) 문장도 다시 만든다. */
    public String hash() {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(render().getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    private static String km(double value) {
        String s = String.format(Locale.ROOT, "%.1f", value);
        return s.endsWith(".0") ? s.substring(0, s.length() - 2) : s;
    }

    /**
     * 몸집 말 — 종류 중립이다(#719). 고양이·기타도 이 입력을 타는데 '소형견' 은 강아지 말이다.
     *
     * <p>종류를 실어 '소형묘' 로 고르지 <b>않는</b> 이유: {@code DogProfileView} 가 모델에 보내는 필드
     * 목록은 개인정보처리방침 v1.8 "AI 주간 요약" 항목(크기 · 나이대)과 묶여 있다. 종류를 더하면 그
     * 문서와 동의 화면이 같이 움직여야 한다. 라벨을 중립으로 두면 목록이 그대로다.
     */
    private static String sizeLabel(String key) {
        return switch (key) {
            case "medium" -> "몸집 중형";
            case "large" -> "몸집 대형";
            default -> "몸집 소형";
        };
    }

    private static String ageLabel(int months) {
        if (months < 12) {
            return "1살 미만";
        }
        int years = months / 12;
        return years >= 8 ? "시니어(" + years + "살)" : years + "살";
    }
}
