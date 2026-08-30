package com.heattrip.heat_trip_backend.chat;

import com.heattrip.heat_trip_backend.support.TestProjectPaths;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 한도가 {@link ChatLimits} 한 곳에만 사는지 잠근다 — 이슈 #74 완료 조건 5.
 *
 * <h2>무엇을 금지하는지 정확히</h2>
 * <p>"{@code 50} 이라는 숫자를 쓰지 마라" 로 짜면 안 된다. 50 은 아무 데나 있고
 * ({@code length = 50}, HTTP 상태, 배열 크기…) 그런 테스트는 오탐으로 며칠 만에 지워진다.
 * 그래서 <b>두 가지만</b> 금지한다. 둘 다 {@link FixedChatLimits} 한 파일은 예외다.
 *
 * <ol>
 *   <li><b>한도 어휘와 정수 리터럴이 같은 줄에 있는 것.</b> 어휘는 {@link #LIMIT_VOCABULARY}
 *       이고, 밑줄을 지우고 소문자로 만든 뒤 비교한다 — 그래야 {@code MAX_MEMBERS} 와
 *       {@code maxMembers} 를 한 목록으로 잡는다.
 *       <br>{@code private static final int MAX_MEMBERS = 50;} → 걸린다.
 *       <br>{@code int cap = chatLimits.maxMembersPerRoom(userId);} → 안 걸린다(숫자가 없다).
 *       <br>{@code @Column(name = "max_uses")} → 안 걸린다(숫자가 없다).</li>
 *   <li><b>{@code Duration.of…} 로 기간을 직접 만드는 것.</b> chat 이 다루는 기간 상수는
 *       초대코드 유효기간 하나뿐이라 이 금지에는 오탐 여지가 없다.</li>
 * </ol>
 *
 * <p><b>주석은 먼저 걷는다.</b> 안 걷으면 "정원 50명의 근거는…" 이라는 javadoc 이 걸린다.
 * 규칙을 설명하는 글을 그 규칙이 막으면 아무도 설명을 안 쓰게 된다.
 *
 * <p>마지막 검사는 <b>장치가 살아 있는지</b>를 본다 — 구현체에 실제로 50 과 7 이 있어야 한다.
 * 값이 사라지면 위 두 검사는 아무것도 없는 패키지를 훑고 조용히 통과한다.
 *
 * <p>스프링을 띄우지 않는다. 구현체를 {@code new} 로 만들고 소스를 파일로 읽으면 되는 일이다(#21).
 */
class ChatLimitsTest {

    private static final String CHAT_SOURCE_DIR =
            "src/main/java/com/heattrip/heat_trip_backend/chat";
    private static final String IMPLEMENTATION_FILE = "FixedChatLimits.java";

    /** 밑줄을 지우고 소문자로 만든 뒤 찾는 낱말. 한도를 뜻하는 <b>복합어</b>만 넣는다. */
    private static final List<String> LIMIT_VOCABULARY = List.of(
            "maxmembers", "memberlimit", "roomcapacity",
            "invitettl", "inviteexpiry",
            "maxinviteuses", "maxuses", "uselimit",
            "정원");

    private static final Pattern INTEGER_LITERAL = Pattern.compile("(?<![\\w.])\\d+");

    private final ChatLimits limits = new FixedChatLimits();

    // ─────────────────── 지금의 값 ───────────────────

    @Test
    @DisplayName("구현체는 인자를 무시하고 상수를 돌려준다 — 50명 · 7일 · 무제한")
    void fixedImplementation_answersTheSameForEveryUser() {
        assertThat(limits.maxMembersPerRoom(1L)).isEqualTo(50);
        assertThat(limits.maxMembersPerRoom(999_999L))
                .as("플랜 표가 없으므로 사용자가 달라도 값이 같다. 이게 달라지는 날 이 파일 하나만 고친다")
                .isEqualTo(limits.maxMembersPerRoom(1L));

        assertThat(limits.inviteTtl(1L)).isEqualTo(Duration.ofDays(7));
        assertThat(limits.maxInviteUses(1L))
                .as("null 이 무제한이다. 0 을 무제한으로 쓰면 '0회 사용 가능' 과 구분이 안 된다")
                .isNull();
    }

    @Test
    @DisplayName("세 메서드가 전부 사용자 id 를 받는다 — 호출부가 플랜을 모른다는 것이 이 인터페이스의 요점이다")
    void everyLimit_isAskedPerUser() {
        List<String> offenders = new ArrayList<>();
        for (Method method : ChatLimits.class.getDeclaredMethods()) {
            Class<?>[] parameters = method.getParameterTypes();
            if (parameters.length != 1 || parameters[0] != long.class) {
                offenders.add(method.getName() + java.util.Arrays.toString(parameters));
            }
        }

        assertThat(ChatLimits.class.getDeclaredMethods())
                .as("한도는 셋이다 — 정원 · 초대 유효기간 · 초대 사용 횟수")
                .hasSize(3);
        assertThat(offenders)
                .as("인자를 없애면 호출부가 '누구의 한도인가' 를 물을 수 없게 되고, 플랜이 생기는 날 "
                        + "호출부를 전부 고쳐야 한다. 지금 인자를 무시하는 것과 인자가 없는 것은 다르다")
                .isEmpty();
    }

    // ─────────────────── 우회 금지 ───────────────────

    @Test
    @DisplayName("한도 상수를 서비스 코드에 직접 적으면 걸린다 — 어휘와 숫자가 같은 줄에 있는 것을 막는다")
    void limitConstants_liveOnlyInTheImplementation() throws IOException {
        List<String> offenders = new ArrayList<>();

        for (Path file : chatSourceFilesExceptImplementation()) {
            String[] lines = stripComments(Files.readString(file, StandardCharsets.UTF_8))
                    .split("\\R");
            for (int i = 0; i < lines.length; i++) {
                String normalized = lines[i].toLowerCase().replace("_", "");
                boolean mentionsLimit = LIMIT_VOCABULARY.stream().anyMatch(normalized::contains);
                if (mentionsLimit && INTEGER_LITERAL.matcher(lines[i]).find()) {
                    offenders.add("%s:%d  %s".formatted(
                            file.getFileName(), i + 1, lines[i].strip()));
                }
            }
        }

        assertThat(offenders)
                .as("""
                        한도는 ChatLimits 가 답한다. 호출부에 숫자를 적으면 플랜이 생기는 날 \
                        고쳐야 할 자리가 코드 전체로 흩어지고, 그때 하나를 빠뜨리면 \
                        '어떤 화면에서는 50명, 어떤 화면에서는 100명' 이 된다 (ADR-0011 결정 10).
                        값을 바꾸려면 FixedChatLimits 를 고쳐라.""")
                .isEmpty();
    }

    @Test
    @DisplayName("기간을 직접 만들지 않는다 — chat 의 기간 상수는 초대 유효기간 하나뿐이다")
    void durationsAreNotBuiltOutsideTheImplementation() throws IOException {
        List<String> offenders = new ArrayList<>();

        for (Path file : chatSourceFilesExceptImplementation()) {
            String source = stripComments(Files.readString(file, StandardCharsets.UTF_8));
            if (source.contains("Duration.of")) {
                offenders.add(file.getFileName().toString());
            }
        }

        assertThat(offenders)
                .as("Duration.ofDays(7) 를 호출부에 적는 것이 ChatLimits.inviteTtl 을 우회하는 "
                        + "가장 흔한 모양이다")
                .isEmpty();
    }

    @Test
    @DisplayName("그 값들이 실제로 구현체에 있다 — 없으면 위 두 검사는 빈 패키지를 훑고 통과한다")
    void theImplementationIsWhereTheNumbersActuallyLive() throws IOException {
        String source = Files.readString(
                TestProjectPaths.requireFile(CHAT_SOURCE_DIR + "/" + IMPLEMENTATION_FILE),
                StandardCharsets.UTF_8);

        assertThat(source)
                .as("정원 50 이 여기 없으면 값이 다른 어딘가로 옮겨 간 것이다")
                .contains("50");
        assertThat(source)
                .as("초대 유효기간 7일이 여기 없으면 값이 다른 어딘가로 옮겨 간 것이다")
                .contains("Duration.ofDays(7)");
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private static List<Path> chatSourceFilesExceptImplementation() throws IOException {
        Path root = TestProjectPaths.requireDirectory(CHAT_SOURCE_DIR);
        try (Stream<Path> files = Files.walk(root)) {
            List<Path> found = files
                    .filter(p -> p.toString().endsWith(".java"))
                    .filter(p -> !p.getFileName().toString().equals(IMPLEMENTATION_FILE))
                    .sorted()
                    .toList();
            if (found.isEmpty()) {
                throw new IllegalStateException(root + " 아래에 검사할 소스가 없다.");
            }
            return found;
        }
    }

    /** 주석을 걷는다 — "정원 50명의 근거" 같은 javadoc 이 걸리면 이 테스트는 곧 지워진다. */
    private static String stripComments(String source) {
        return source
                .replaceAll("(?s)/\\*.*?\\*/", "")
                .replaceAll("//[^\\n]*", "");
    }
}
