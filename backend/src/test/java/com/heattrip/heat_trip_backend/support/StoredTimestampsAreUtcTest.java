package com.heattrip.heat_trip_backend.support;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.regex.Pattern;
import java.util.TimeZone;
import java.util.stream.Stream;

import com.heattrip.heat_trip_backend.care.CareTime;
import com.heattrip.heat_trip_backend.care.entity.CareLog;
import com.heattrip.heat_trip_backend.chat.ChatTime;
import com.heattrip.heat_trip_backend.community.CommunityTime;
import com.heattrip.heat_trip_backend.community.entity.Comment;
import com.heattrip.heat_trip_backend.community.entity.Post;
import com.heattrip.heat_trip_backend.community.entity.Reaction;
import com.heattrip.heat_trip_backend.dog.DogTime;
import com.heattrip.heat_trip_backend.dog.entity.Dog;
import com.heattrip.heat_trip_backend.moderation.ModerationTime;
import com.heattrip.heat_trip_backend.moderation.entity.Block;
import com.heattrip.heat_trip_backend.push.PushTime;
import com.heattrip.heat_trip_backend.push.entity.DeviceToken;
import com.heattrip.heat_trip_backend.push.entity.PushPreference;
import com.heattrip.heat_trip_backend.walk.entity.Walk;
import com.heattrip.heat_trip_backend.chat.entity.ChatMessage;
import com.heattrip.heat_trip_backend.chat.entity.ChatRoom;
import com.heattrip.heat_trip_backend.chat.entity.ChatRoomInvite;
import com.heattrip.heat_trip_backend.chat.entity.ChatRoomMember;
import com.heattrip.heat_trip_backend.group.entity.FamilyGroup;
import com.heattrip.heat_trip_backend.user.UserTime;
import com.heattrip.heat_trip_backend.user.entity.User;

import jakarta.persistence.Entity;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 표에 들어가는 시각이 <b>JVM 기본 존이 아니라 UTC</b> 인지 본다 — 이슈 #248.
 *
 * <h2>무엇이 문제였나</h2>
 * <p>엔티티 일곱의 {@code @PrePersist} 가 {@code LocalDateTime.now()} 를 썼다. 그건
 * <b>JVM 기본 존</b>을 읽는다 — 개발 기계는 KST 고 배포 컨테이너는 UTC 라, 같은 코드가
 * 환경마다 다른 값을 넣는다. dev DB 에 실제로 두 존이 섞여 있었다: {@code users} 15번은
 * {@code 01:07:38}(JVM 존)에 만들어졌고 0.78초 뒤 쓴 글의 {@code created_at} 은
 * {@code 01:07:39}(UTC 규약)였다 — 그 행을 쓴 JVM 은 UTC 였다는 뜻이고, 같은 표의 다른
 * 행들은 KST 로 들어와 있다.
 *
 * <p>그 값이 그대로 응답에 실리면서 {@code format: date-time} 필드 열하나가 <b>오프셋 없이</b>
 * 나갔다. 앱의 {@code DateTime.parse} 는 오프셋 없는 문자열을 기기 지역 시각으로 읽는다.
 *
 * <h2>왜 존을 <b>바꿔서</b> 재는가</h2>
 * <p>이 검사의 핵심이다. 그냥 "{@code nowUtc()} 가 지금과 가깝다" 를 재면
 * <b>CI(UTC)에서는 되돌려도 초록불</b>이다 — 거기서는 {@code LocalDateTime.now()} 가 이미
 * UTC 이기 때문이다. #247 에서 정확히 그 헛초록을 한 번 봤다({@code CareTimeZoneTest} 가
 * 같은 이유로 {@code TimeZone.setDefault} 를 쓴다).
 *
 * <p>그래서 JVM 기본 존을 <b>{@code Asia/Seoul} 로 강제한 뒤</b> 잰다. 되돌리면 값이
 * 9시간 움직이므로 개발 기계에서도 CI 에서도 똑같이 빨간불이 난다.
 *
 * <p>스프링을 안 띄운다(#21).
 */
class StoredTimestampsAreUtcTest {

    /**
     * 이 검사가 커버하는 엔티티. <b>{@code @PrePersist}/{@code @PreUpdate} 로 시각을 찍는
     * 것들</b>이고, 그 값이 {@code format: date-time} 응답으로 나간다.
     */
    private static final List<Class<?>> WRITERS = List.of(
            ChatMessage.class, ChatRoom.class, ChatRoomMember.class,
            ChatRoomInvite.class,
            FamilyGroup.class, User.class,
            // #306 — 훑는 범위를 chat·group·user 에서 전체로 넓히면서 들어온 반려 축 엔티티.
            Dog.class, CareLog.class, Walk.class,
            Post.class, Comment.class, Reaction.class, Block.class,
            // #83 — 기기 토큰과 알림 설정.
            DeviceToken.class, PushPreference.class,
            // #418 — 일정표. on_date·at_time 은 사람이 고른 벽시계라 UTC 로 안 눕힌다
            // (ScheduleTime javadoc). 이 검사가 보는 것은 created_at·updated_at·done_at 이다.
            com.heattrip.heat_trip_backend.schedule.entity.Schedule.class,
            // #417 — 크루. created_at·updated_at 둘 다 서버가 찍는 순간이라 UTC 로 눕힌다
            // (CrewTime). 사람이 고른 벽시계가 이 표에는 하나도 없다.
            com.heattrip.heat_trip_backend.crew.entity.Crew.class);

    /**
     * 훅이 있는데 <b>일부러 목록에 안 넣는</b> 엔티티. 이름을 여기 적는 이유는 "몰라서 빠진 것"
     * 과 "알고 뺀 것" 을 가르기 위해서다 — {@code theWriterListCoversEveryEntityWithALifecycleHook}
     * 가 이 둘 밖의 엔티티를 잡는다(#306).
     *
     * <p><b>지금은 비어 있다.</b> 2026-09-06 까지는 감정 여행·관광 수집 시절의 엔티티 열 개
     * (bookmark·feedback·schedules·social·tour)가 여기 있었다 — 지우지 않고 격리하던 것들이다.
     * #94 로 그 패키지를 지웠다. 되살릴 것이 없으니 새 엔티티는 전부 {@code WRITERS} 로 간다.
     */
    /** 소스에서 훅 <b>애노테이션</b> 줄만 찾는다 — 본문·javadoc 의 언급은 세지 않는다. */
    private static final Pattern LIFECYCLE_ANNOTATION =
            Pattern.compile("(?m)^\\s*@(PrePersist|PreUpdate)\\b");

    private static final Set<String> KNOWN_JVM_ZONE_LEGACY = Set.of();

    /** 되돌리면 값이 이만큼 움직인다. DST 가 없어 사시사철 같다. */
    private static final ZoneId FORCED = ZoneId.of("Asia/Seoul");

    private static final Duration FORCED_OFFSET = Duration.ofHours(9);

    // ─────────────────── A. 헬퍼가 존을 안 읽는다 ───────────────────

    @Test
    @DisplayName("nowUtc() 는 JVM 기본 존이 Asia/Seoul 이어도 UTC 를 준다 — 안 그러면 9시간 어긋난다")
    void nowUtc_ignoresTheJvmDefaultZone() {
        withDefaultZone(FORCED, () -> {
            for (String label : List.of("ChatTime", "UserTime", "DogTime", "CareTime",
                    "CommunityTime", "ModerationTime", "PushTime", "ScheduleTime")) {
                LocalDateTime written = switch (label) {
                    case "ChatTime" -> ChatTime.nowUtc();
                    case "UserTime" -> UserTime.nowUtc();
                    case "DogTime" -> DogTime.nowUtc();
                    case "CareTime" -> CareTime.nowUtc();
                    case "CommunityTime" -> CommunityTime.nowUtc();
                    case "PushTime" -> PushTime.nowUtc();
                    case "ScheduleTime" ->
                            com.heattrip.heat_trip_backend.schedule.ScheduleTime.nowUtc();
                    default -> ModerationTime.nowUtc();
                };

                // 기본 존의 벽시계와 정확히 9시간 벌어져 있어야 한다. "지금과 가깝다" 로 재면
                // CI(UTC)에서 되돌려도 통과한다 — 그게 이 단언이 차이를 재는 이유다.
                Duration gap = Duration.between(written, LocalDateTime.now());
                assertThat(gap)
                        .as("%s.nowUtc() 가 JVM 존을 따라갔다 — LocalDateTime.now() 로 되돌아간 것이다", label)
                        .isCloseTo(FORCED_OFFSET, Duration.ofSeconds(10));
            }
        });
    }

    @Test
    @DisplayName("nowUtc(clock) 은 시계의 존을 안 읽는다 — 빈이 주는 시계는 Asia/Seoul 이다")
    void nowUtcWithClock_readsTheInstantNotTheZone() {
        // ClockConfig 가 주는 것과 같은 모양: 존이 박힌 시계. 그 존은 케어의 "오늘" 경계용이고
        // 표에 넣는 값이 따라가면 안 된다 — 따라가면 같은 표 안에서 존이 다시 둘이 된다.
        Instant moment = Instant.parse("2026-09-03T00:30:00Z");
        Clock seoulClock = Clock.fixed(moment, FORCED);

        assertThat(ChatTime.nowUtc(seoulClock))
                .as("시계의 존을 따라가면 09:30 이 된다")
                .isEqualTo(LocalDateTime.of(2026, 9, 3, 0, 30));
        assertThat(ChatTime.nowUtc(seoulClock))
                .isNotEqualTo(LocalDateTime.now(seoulClock));
        assertThat(DogTime.nowUtc(seoulClock))
                .as("DogService.delete 가 이 시계로 deleted_at 을 찍는다(#156) — 존을 따라가면 9시간 어긋난다")
                .isEqualTo(LocalDateTime.of(2026, 9, 3, 0, 30));
        assertThat(ModerationTime.nowUtc(seoulClock))
                .isEqualTo(LocalDateTime.of(2026, 9, 3, 0, 30));
    }

    @Test
    @DisplayName("toInstant 가 저장값을 UTC 로 세운다 — null 은 null 이다")
    void toInstant_buildsTheMomentInUtc() {
        LocalDateTime stored = LocalDateTime.of(2026, 9, 3, 0, 30);

        assertThat(ChatTime.toInstant(stored)).isEqualTo(Instant.parse("2026-09-03T00:30:00Z"));
        assertThat(UserTime.toInstant(stored)).isEqualTo(Instant.parse("2026-09-03T00:30:00Z"));
        assertThat(ChatTime.toInstant(stored))
                .as("서비스 존에서 세우면 같은 문자열이 9시간 앞의 순간이 된다")
                .isNotEqualTo(stored.atZone(FORCED).toInstant());

        assertThat(ChatTime.toInstant(null)).isNull();
        assertThat(UserTime.toInstant(null)).isNull();
    }

    // ─────────────────── B. 엔티티가 실제로 그것을 쓴다 ───────────────────

    @Test
    @DisplayName("엔티티의 @PrePersist 가 찍는 값이 UTC 다 — 라이프사이클 훅을 실제로 불러서 본다")
    void everyLifecycleHook_writesUtc() {
        List<String> offenders = new ArrayList<>();

        withDefaultZone(FORCED, () -> {
            for (Class<?> type : WRITERS) {
                for (Method hook : lifecycleHooksOf(type)) {
                    LocalDateTime written = invokeAndReadTheStamp(type, hook);
                    if (written == null) {
                        offenders.add(type.getSimpleName() + "." + hook.getName()
                                + " 이 아무 시각도 안 찍었다 — 이 검사가 헛돌고 있다");
                        continue;
                    }
                    Duration gap = Duration.between(written, LocalDateTime.now());
                    if (gap.minus(FORCED_OFFSET).abs().compareTo(Duration.ofSeconds(10)) > 0) {
                        offenders.add("%s.%s → %s (기본 존과의 차 %s, 9시간이어야 한다)"
                                .formatted(type.getSimpleName(), hook.getName(), written, gap));
                    }
                }
            }
        });

        assertThat(offenders)
                .as("""
                        LocalDateTime.now() 로 되돌아가면 여기가 빨간불이다. 그 함수는 JVM 기본 \
                        존을 읽으므로 개발 기계(KST)와 배포 컨테이너(UTC)가 같은 코드로 다른 \
                        값을 넣는다 — 한 표 안에 두 존이 섞이고, 응답의 시각이 9시간 움직인다.""")
                .isEmpty();
    }

    @Test
    @DisplayName("훅을 가진 엔티티를 하나도 안 빠뜨렸다 — 목록이 낡으면 새 표가 조용히 밖에 남는다")
    void theWriterListCoversEveryEntityWithALifecycleHook() {
        List<String> missing = new ArrayList<>();
        List<String> covered = WRITERS.stream().map(Class::getSimpleName).toList();

        for (Path file : entitySourceFiles()) {
            String source = read(file);
            String name = file.getFileName().toString().replace(".java", "");
            boolean isEntity = source.contains("@Entity");
            // 애노테이션 줄만 센다 — javadoc 이 "@PrePersist 를 안 두는 이유" 를 적은 UserConsent 가 잡혔다.
            boolean stamps = LIFECYCLE_ANNOTATION.matcher(source).find();
            if (isEntity && stamps && !covered.contains(name)
                    && !KNOWN_JVM_ZONE_LEGACY.contains(name)) {
                missing.add(name + "  (" + file.getParent().getFileName() + ")");
            }
        }

        assertThat(missing)
                .as("""
                        시각을 찍는 엔티티가 있는데 WRITERS 에도 KNOWN_JVM_ZONE_LEGACY 에도 없다. \
                        목록을 안 늘리면 그 표만 JVM 존으로 남는다 — Dog 가 정확히 그렇게 빠져 있었다(#306). \
                        새 엔티티면 WRITERS 에 넣고 UTC 헬퍼를 쓰게 하라. 레거시면 이유와 함께 \
                        KNOWN_JVM_ZONE_LEGACY 에 적어라.""")
                .isEmpty();
        assertThat(covered).hasSize(WRITERS.size());
    }

    // ─────────────────────────── 도구 ───────────────────────────

    /**
     * JVM 기본 존을 바꿔 두고 돌린다. <b>{@code finally} 로 반드시 되돌린다</b> — 안 되돌리면
     * 같은 JVM 에서 뒤에 도는 테스트가 다른 존을 보게 된다.
     */
    private static void withDefaultZone(ZoneId zone, Runnable body) {
        TimeZone original = TimeZone.getDefault();
        try {
            TimeZone.setDefault(TimeZone.getTimeZone(zone));
            body.run();
        } finally {
            TimeZone.setDefault(original);
        }
    }

    private static List<Method> lifecycleHooksOf(Class<?> type) {
        List<Method> hooks = new ArrayList<>();
        for (Method method : type.getDeclaredMethods()) {
            if (method.isAnnotationPresent(PrePersist.class)
                    || method.isAnnotationPresent(PreUpdate.class)) {
                method.setAccessible(true);
                hooks.add(method);
            }
        }
        assertThat(hooks)
                .as("%s 에서 @PrePersist/@PreUpdate 를 못 찾았다 — 못 찾고 통과하면 이 검사는 "
                        + "아무것도 지키지 않는다", type.getSimpleName())
                .isNotEmpty();
        return hooks;
    }

    /**
     * 빈 엔티티를 만들어 훅을 부르고, 그것이 채운 <b>가장 최근</b> 시각 필드를 읽는다.
     *
     * <p>필드 이름을 열거하지 않는다 — {@code created_at}·{@code joined_at}·{@code updated_at}
     * 로 제각각이고, 열거하면 이름이 하나 늘 때마다 이 검사가 조용히 그것을 놓친다.
     */
    private static LocalDateTime invokeAndReadTheStamp(Class<?> type, Method hook) {
        try {
            var constructor = type.getDeclaredConstructor();
            constructor.setAccessible(true); // 대부분 @NoArgsConstructor(PROTECTED) 다
            Object entity = constructor.newInstance();
            hook.invoke(entity);

            LocalDateTime latest = null;
            for (java.lang.reflect.Field field : type.getDeclaredFields()) {
                if (field.getType() != LocalDateTime.class) {
                    continue;
                }
                field.setAccessible(true);
                LocalDateTime value = (LocalDateTime) field.get(entity);
                if (value != null && (latest == null || value.isAfter(latest))) {
                    latest = value;
                }
            }
            return latest;
        } catch (ReflectiveOperationException e) {
            throw new IllegalStateException(type.getSimpleName() + "." + hook.getName()
                    + " 을 부르지 못했다", e);
        }
    }

    /**
     * <b>모든</b> 모듈의 엔티티 소스 — {@code entity}·{@code domain} 디렉터리 아래의 자바 파일.
     * #306 까지 {@code chat}·{@code group}·{@code user} 셋만 훑었고, 그래서 {@code Dog} 가 JVM 존을
     * 찍는 것을 이 검사가 못 봤다. 범위를 목록으로 적으면 새 모듈이 조용히 밖에 남는다.
     */
    private static List<Path> entitySourceFiles() {
        List<Path> found = new ArrayList<>();
        Path base = TestProjectPaths.requireDirectory("src/main/java/com/heattrip/heat_trip_backend");
        try (Stream<Path> walk = Files.walk(base)) {
            walk.filter(Files::isRegularFile)
                    .filter(p -> p.getFileName().toString().endsWith(".java"))
                    .filter(p -> {
                        String parent = p.getParent().getFileName().toString();
                        return parent.equals("entity") || parent.equals("domain");
                    })
                    .forEach(found::add);
        } catch (IOException e) {
            throw new UncheckedIOException(base + " 를 훑지 못했다", e);
        }
        assertThat(found)
                .as("엔티티 소스를 하나도 못 읽었다면 이 검사는 아무것도 지키지 않는다")
                .isNotEmpty();
        return found;
    }

    private static String read(Path file) {
        try {
            return Files.readString(file, StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new UncheckedIOException(file + " 를 읽지 못했다", e);
        }
    }

    /** 쓰이지 않지만 남겨 둔다 — 규약이 UTC 라는 것을 이 파일 안에서 한 번 더 못 박는다. */
    static final ZoneOffset DOCTRINE = ZoneOffset.UTC;
}
