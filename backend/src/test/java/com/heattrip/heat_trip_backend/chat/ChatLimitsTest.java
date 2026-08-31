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
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 한도가 {@link ChatLimits} 한 곳에만 사는지 잠근다 — 이슈 #74 완료 조건 5.
 *
 * <h2>무엇을 금지하는지 정확히</h2>
 * <p>둘 다 {@link FixedChatLimits} 한 파일은 예외다. 그리고 <b>애너테이션은 먼저 걷는다</b> —
 * {@code @Column(name = "max_uses", columnDefinition = "int default 0")} 는 스키마 선언이지
 * 한도가 아닌데, 안 걷으면 그런 줄이 걸린다(실측으로 빨간불을 봤다). 컬럼 정의는 애너테이션에
 * 살고 한도 판정은 문장에 산다 — 그 선으로 가른다.
 *
 * <ol>
 *   <li><b>{@link ChatLimits} 가 지금 돌려주는 값과 같은 정수 리터럴.</b> 이름이 아니라
 *       <b>값</b>을 본다. {@code ROOM_LIMIT = 50} 도 {@code CAPACITY = 50} 도
 *       {@code if (members >= 50)} 도 전부 걸린다.
 *       <br>값은 {@code new FixedChatLimits()} 에게 실행 시점에 물어서 만든다 — 한도를 바꾸면
 *       금지 목록도 저절로 따라간다.</li>
 *   <li><b>기간을 직접 만드는 것</b> — {@code Duration.of…} 와 {@code plusDays}/{@code plusHours}
 *       계열. chat 이 다루는 기간은 초대 유효기간 하나뿐이라 이 금지에는 오탐 여지가 없다.
 *       {@code expires_at} 이 {@code LocalDateTime} 이라 실제 코드는 {@code Duration.ofDays(7)}
 *       보다 {@code now().plusDays(7)} 로 적힐 가능성이 높다 — 그쪽이 안 막히면 유효기간
 *       우회는 사실상 무방비다.</li>
 *   <li><b>한도 어휘와 정수 리터럴이 같은 줄에 있는 것.</b> 어휘는 {@link #LIMIT_VOCABULARY}
 *       이고 밑줄을 지우고 소문자로 만든 뒤 비교한다. 위 1번이 값으로 못 잡는 것
 *       ({@code maxInviteUses} 는 지금 {@code null} 이라 금지할 값이 없다)을 받친다.</li>
 * </ol>
 *
 * <h2>왜 어휘 목록만으로는 안 되는가</h2>
 * <p>처음 판은 3번 하나였다. {@code MAX_MEMBERS_PER_ROOM = 50} 은 잡지만
 * {@code ROOM_LIMIT = 50}·{@code CAPACITY = 50}·이름 없는 리터럴은 전부 통과했다(실측).
 * 완료 조건 5 가 <b>이름 짓기 운</b>에 걸려 있었다는 뜻이다. 목록을 늘리는 것은 같은 실패를
 * 미루는 것이라, 축을 이름에서 <b>값</b>으로 옮겼다.
 *
 * <p><b>값 기준이 안전한 근거는 실측이다.</b> 주석과 애너테이션을 걷고 나면
 * {@code FixedChatLimits} 밖 chat main 소스에 남는 정수 리터럴은 {@code usedCount = 0} 하나뿐이다.
 * 그래서 50 을 금지해도 오탐이 없다. 다만 한도가 아주 작은 수(1·2)로 바뀌면 이 축은 못 쓴다 —
 * 그 경우를 위해 {@link #TOO_COMMON_TO_BAN} 아래 값은 금지하지 않고, 그때는 2·3번이 받친다.
 *
 * <h2>호출부 검사 — #74 가 #78 로 미뤄 뒀던 것</h2>
 * <p>이 javadoc 은 원래 "가장 강한 형태는 호출 그래프로 보는 것인데 이 브랜치에는 chat
 * 서비스가 0개라 호출부가 없다. 그 검사는 #78 에서 함께 넣는다" 로 끝났다. 호출부는 #75 의
 * {@code ChatRoomService} 로 이미 생겼고, #78 이 그 약속을 지킨다 —
 * {@link #everyLimit_isAskedThroughTheInterfaceAtItsCallSite()} 가 세 한도가 <b>전부</b>
 * {@code limits.…(…)} 호출로 나타나는지 본다.
 *
 * <p><b>여전히 호출 그래프는 아니다.</b> 이 검사가 잡는 것은 "한도를 묻는 호출이 사라졌다"
 * 이고, 잡지 못하는 것은 "호출은 해 두고 그 답을 판정에 안 쓴다" 이다. 후자는 값 검사(1번)와
 * 어휘 검사(3번)가 받친다 — 판정에 쓸 숫자를 어딘가에는 적어야 하기 때문이다.
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

    /**
     * 이보다 작은 한도 값은 리터럴로 금지하지 않는다. {@code 0}·{@code 1}·{@code 2} 는 코드
     * 어디에나 있어서 금지하면 오탐만 남고, 시끄러운 게이트는 지워진다.
     */
    private static final int TOO_COMMON_TO_BAN = 10;

    private static final Pattern INTEGER_LITERAL = Pattern.compile("(?<![\\w.])(\\d+)(?![\\w.])");

    /** 기간을 직접 만드는 모양. chat 밖에서 날짜 산술을 하는 자리는 없다. */
    private static final Pattern BUILDS_A_DURATION = Pattern.compile(
            "Duration\\.of|\\.plus(Days|Hours|Minutes|Seconds|Weeks|Months)\\b"
                    + "|\\.minus(Days|Hours|Minutes|Seconds|Weeks|Months)\\b");

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

    @Test
    @DisplayName("세 한도가 전부 호출부에서 실제로 물어진다 — 호출이 사라지면 상수는 남고 판정만 조용히 없어진다")
    void everyLimit_isAskedThroughTheInterfaceAtItsCallSite() throws IOException {
        StringBuilder chatSources = new StringBuilder();
        for (Path file : chatSourceFilesExceptImplementation()) {
            chatSources.append(scannableSourceOf(file)).append('\n');
        }
        String sources = chatSources.toString();

        List<String> missing = new ArrayList<>();
        for (Method method : ChatLimits.class.getDeclaredMethods()) {
            if (!sources.contains("." + method.getName() + "(")) {
                missing.add(method.getName());
            }
        }

        assertThat(missing)
                .as("""
                        #74 가 이 검사를 #78 로 미뤘다 — 그때는 chat 에 서비스가 0개라 호출부가 \
                        없었다. 지금은 ChatRoomService 가 셋을 다 부른다.
                        값 검사(리터럴 금지)만으로는 '한도를 아예 안 묻는' 회귀를 못 잡는다. \
                        정원 검사를 통째로 지우면 리터럴도 어휘도 남지 않아 전부 초록불이고, \
                        그때 방은 인원 제한 없이 커진다.
                        한도가 늘면 그 호출부도 함께 생겨야 한다 — 인터페이스에만 더하고 아무도 \
                        안 부르면 여기서 걸린다.""")
                .isEmpty();
    }

    // ─────────────────── 우회 금지 ───────────────────

    @Test
    @DisplayName("ChatLimits 가 돌려주는 값을 서비스 코드에 리터럴로 적으면 걸린다 — 이름이 아니라 값을 본다")
    void limitValues_appearNowhereButTheImplementation() throws IOException {
        Set<Integer> banned = bannedLimitValues();

        assertThat(banned)
                .as("금지할 값이 하나도 없으면 이 검사는 아무것도 지키지 않는다 — "
                        + "한도가 전부 %d 미만으로 내려갔다면 이 축은 못 쓴다", TOO_COMMON_TO_BAN)
                .isNotEmpty();

        List<String> offenders = new ArrayList<>();
        for (Path file : chatSourceFilesExceptImplementation()) {
            String[] lines = scannableSourceOf(file).split("\\R", -1);
            for (int i = 0; i < lines.length; i++) {
                Matcher m = INTEGER_LITERAL.matcher(lines[i]);
                while (m.find()) {
                    if (banned.contains(Integer.valueOf(m.group(1)))) {
                        offenders.add("%s:%d  %s".formatted(
                                file.getFileName(), i + 1, lines[i].strip()));
                    }
                }
            }
        }

        assertThat(offenders)
                .as("""
                        한도는 ChatLimits 가 답한다. 어휘 목록으로는 ROOM_LIMIT·CAPACITY·이름 없는 \
                        리터럴이 전부 빠져나가서(실측) 축을 값으로 옮겼다.
                        컬럼 길이 같은 스키마 선언은 애너테이션에 살고 여기서 빠진다 — \
                        @Column(length = 50) 은 걸리지 않는다.
                        값을 바꾸려면 FixedChatLimits 를 고쳐라 (ADR-0011 결정 10).""")
                .isEmpty();
    }

    @Test
    @DisplayName("그 값 검사가 실제로 잡는다 — 어휘 목록이 놓쳤던 세 모양을 전부 본다")
    void theValueScannerActuallyCatchesTheBypasses() {
        Set<Integer> banned = bannedLimitValues();
        // 샘플을 50 으로 박지 않는다 — 한도를 바꾸면 이 자기검증까지 빨간불이 나서,
        // 값을 고치는 사람이 게이트가 고장난 줄 알게 된다.
        int cap = limits.maxMembersPerRoom(1L);

        assertThat(bannedLiteralsIn("private static final int ROOM_LIMIT = " + cap + ";", banned))
                .as("이름이 목록에 없어도 걸려야 한다 — 이것이 check 전체를 초록으로 통과했었다")
                .isNotEmpty();
        assertThat(bannedLiteralsIn("private static final int CAPACITY = " + cap + ";", banned))
                .isNotEmpty();
        assertThat(bannedLiteralsIn("if (currentMembers >= " + cap + ") { throw x; }", banned))
                .as("이름조차 없는 리터럴이 가장 잡기 어려운 모양이다")
                .isNotEmpty();

        assertThat(bannedLiteralsIn("int cap = chatLimits.maxMembersPerRoom(userId);", banned))
                .as("ChatLimits 를 거치는 정당한 코드")
                .isEmpty();
        assertThat(bannedLiteralsIn("private Integer usedCount = 0;", banned))
                .as("한도와 무관한 기본값")
                .isEmpty();
        assertThat(bannedLiteralsIn("status = " + cap + "0;", banned))
                .as("500 은 50 이 아니다 — 리터럴 경계를 안 보면 여기서 오탐이 난다")
                .isEmpty();
    }

    @Test
    @DisplayName("기간을 직접 만들지 않는다 — Duration.of 도 now().plusDays 도 같은 우회다")
    void durationsAreNotBuiltOutsideTheImplementation() throws IOException {
        List<String> offenders = new ArrayList<>();

        for (Path file : chatSourceFilesExceptImplementation()) {
            String[] lines = scannableSourceOf(file).split("\\R", -1);
            for (int i = 0; i < lines.length; i++) {
                if (BUILDS_A_DURATION.matcher(lines[i]).find()) {
                    offenders.add("%s:%d  %s".formatted(
                            file.getFileName(), i + 1, lines[i].strip()));
                }
            }
        }

        assertThat(offenders)
                .as("""
                        Duration.ofDays(7) 만 막으면 유효기간 우회는 사실상 무방비다 — expires_at 이 \
                        LocalDateTime 이라 실제 코드는 now().plusDays(7) 로 적힌다.
                        발급은 ChatLimits.inviteTtl 이 답한 기간을 더하는 것 하나뿐이고, 그 자리는 \
                        FixedChatLimits 다.""")
                .isEmpty();
        assertThat(BUILDS_A_DURATION.matcher("LocalDateTime.now().plusDays(7)").find())
                .as("이 검사가 실제로 그 모양을 잡는지 — 안 잡으면 위 단언은 공허하다")
                .isTrue();
        assertThat(BUILDS_A_DURATION.matcher("createdAt = LocalDateTime.now();").find())
                .as("now() 자체는 정당하다 — @PrePersist 가 그것을 쓴다")
                .isFalse();
    }

    @Test
    @DisplayName("한도 어휘와 숫자가 같은 줄에 있으면 걸린다 — 값이 null 이라 값으로는 못 잡는 것을 받친다")
    void limitVocabulary_carriesNoNumberOutsideTheImplementation() throws IOException {
        List<String> offenders = new ArrayList<>();

        for (Path file : chatSourceFilesExceptImplementation()) {
            String[] lines = scannableSourceOf(file).split("\\R", -1);
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
                        maxInviteUses 는 지금 null 이라 금지할 값이 없다 — 그 자리는 어휘가 받친다.
                        애너테이션은 먼저 걷으므로 @Column(name = "max_uses", …) 는 걸리지 않는다. \
                        컬럼 정의를 한도로 오해하는 오탐이 있으면 이 테스트가 며칠 만에 지워진다.""")
                .isEmpty();
    }

    @Test
    @DisplayName("그 값들이 실제로 구현체에 있다 — 없으면 위 검사들은 빈 패키지를 훑고 통과한다")
    void theImplementationIsWhereTheNumbersActuallyLive() throws IOException {
        String source = Files.readString(
                TestProjectPaths.requireFile(CHAT_SOURCE_DIR + "/" + IMPLEMENTATION_FILE),
                StandardCharsets.UTF_8);

        // contains("50") 으로 두면 같은 파일 javadoc 의 "정원 50명"·"라인 500" 이 항상 참으로
        // 만든다 — 상수를 51 로 바꿔도 이 단언만 초록이었다(실측). 선언에 앵커를 건다.
        assertThat(source)
                .as("정원 50 이 선언 자리에 없으면 값이 다른 어딘가로 옮겨 간 것이다")
                .containsPattern("MAX_MEMBERS_PER_ROOM\\s*=\\s*50\\b");
        assertThat(source)
                .as("초대 유효기간 7일이 여기 없으면 값이 다른 어딘가로 옮겨 간 것이다")
                .contains("Duration.ofDays(7)");
    }

    // ─────────────────────────── 지그 ───────────────────────────

    /**
     * {@link ChatLimits} 가 지금 돌려주는 정수 답 중 리터럴로 금지할 값.
     *
     * <p>구현체에게 실행 시점에 물어서 만든다 — 한도를 바꾸면 금지 목록이 저절로 따라간다.
     * 유효기간은 날짜 단위별로 함께 넣는다({@code plusHours(168)} 도 같은 우회다).
     */
    private Set<Integer> bannedLimitValues() {
        Set<Integer> banned = new LinkedHashSet<>();
        addIfBannable(banned, limits.maxMembersPerRoom(1L));

        Integer maxUses = limits.maxInviteUses(1L);
        if (maxUses != null) {
            addIfBannable(banned, maxUses);
        }

        Duration ttl = limits.inviteTtl(1L);
        addIfBannable(banned, ttl.toDays());
        addIfBannable(banned, ttl.toHours());
        addIfBannable(banned, ttl.toMinutes());
        addIfBannable(banned, ttl.toSeconds());
        return banned;
    }

    private static void addIfBannable(Set<Integer> banned, long value) {
        if (value >= TOO_COMMON_TO_BAN && value <= Integer.MAX_VALUE) {
            banned.add((int) value);
        }
    }

    /** 한 줄에서 금지된 값의 리터럴을 찾는다. 위 검사와 자기검증이 같은 코드를 쓴다. */
    private static List<String> bannedLiteralsIn(String line, Set<Integer> banned) {
        List<String> found = new ArrayList<>();
        Matcher m = INTEGER_LITERAL.matcher(line);
        while (m.find()) {
            if (banned.contains(Integer.valueOf(m.group(1)))) {
                found.add(m.group(1));
            }
        }
        return found;
    }

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

    /** 주석과 스키마 애너테이션을 걷은 소스. 줄 수는 그대로다 — 위반을 파일:줄 로 가리켜야 한다. */
    private static String scannableSourceOf(Path file) throws IOException {
        return stripSchemaAnnotations(
                stripComments(Files.readString(file, StandardCharsets.UTF_8)));
    }

    /**
     * 주석을 걷는다 — "정원 50명의 근거" 같은 javadoc 이 걸리면 이 테스트는 곧 지워진다.
     * 줄바꿈은 남겨 줄 번호를 지킨다.
     */
    private static String stripComments(String source) {
        return blankOut(source, Pattern.compile("(?s)/\\*.*?\\*/|//[^\\n]*"));
    }

    /**
     * <b>스키마 선언 애너테이션</b>만 걷는다 — 컬럼 길이·기본값은 한도가 아니다.
     *
     * <p>{@code @Value("${chat.max-members:50}")} 같은 <b>주입</b>은 일부러 남긴다. 그건 한도를
     * ChatLimits 밖에 두는 진짜 우회라서 걸려야 한다.
     */
    private static String stripSchemaAnnotations(String source) {
        return blankOut(source, Pattern.compile(
                "(?s)@(Column|Table|ColumnDefault|UniqueConstraint|JoinColumn|Index|Size)"
                        + "\\s*\\((?:[^()]|\\([^()]*\\))*\\)"));
    }

    /** 찾은 부분을 지우되 그 안의 줄바꿈은 남긴다. */
    private static String blankOut(String source, Pattern pattern) {
        Matcher m = pattern.matcher(source);
        StringBuilder out = new StringBuilder(source.length());
        int last = 0;
        while (m.find()) {
            out.append(source, last, m.start());
            out.append("\n".repeat((int) m.group().chars().filter(c -> c == '\n').count()));
            last = m.end();
        }
        return out.append(source.substring(last)).toString();
    }
}
