package com.heattrip.heat_trip_backend.care;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.care.entity.CareItem;
import com.heattrip.heat_trip_backend.care.service.CareItemService;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 가족을 만들면 기본 일곱이 들어간다 — 이슈 #560 조각 1.
 *
 * <h2>무엇을 보증하나</h2>
 *
 * <p>목록이 <b>생겨나는 자리</b>는 둘이다. 이미 있던 집은 마이그레이션이 채우고
 * ({@code CareItemMigrationExecutionTest}), <b>새로 만드는 집은 이 경로</b>가 채운다.
 * 둘 중 하나만 있으면 한쪽 집단의 카드가 통째로 빈다.
 *
 * <h2>왜 이벤트인가 — 그리고 왜 그게 눈에 안 보여야 하나</h2>
 *
 * <p>{@code group} 이 {@code care} 를 직접 부르면 거꾸로 된 의존이 생긴다
 * ({@code FamilyGroupCreated} javadoc). 대신 {@code AFTER_COMMIT} 리스너가 받는데, 그건
 * <b>비동기가 아니라</b> 같은 스레드에서 커밋 직후에 돈다 — 그래서 여기 테스트가
 * {@code POST /api/groups} 응답 직후에 바로 세어도 일곱이 있다. 비동기로 두면 이 단언이
 * 흔들리고, 실제 화면도 그만큼 비어 보인다.
 */
@SpringBootTest
@AutoConfigureMockMvc
class CareItemSeedIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final AtomicLong SEQUENCE = new AtomicLong();

    @Autowired private MockMvc mockMvc;
    @Autowired private ObjectMapper objectMapper;
    @Autowired private UserRepository users;
    @Autowired private JWTProvider jwtProvider;
    @Autowired private CareItemService careItems;

    @Test
    @DisplayName("가족을 만들면 기본 일곱이 순서대로 들어간다 — 첫 화면이 비면 안 된다")
    void creatingAFamilySeedsTheSeven() throws Exception {
        Account mom = account("엄마");

        long groupId = createGroup(mom);

        assertThat(careItems.listOf(groupId))
                .extracting(CareItem::getName)
                .containsExactly("물", "밥", "산책", "투약", "병원", "배변", "마킹");
    }

    @Test
    @DisplayName("기본 일곱은 아이를 안 고른다 — 물·밥·산책은 모든 아이에게 하는 일이다")
    void theDefaultsApplyToEveryDog() throws Exception {
        Account mom = account("엄마");

        long groupId = createGroup(mom);

        assertThat(careItems.listOf(groupId))
                .allSatisfy(item -> assertThat(item.getDog())
                        .as("아이를 고르면 %s 가 한 아이 카드에만 뜬다", item.getName())
                        .isNull());
    }

    @Test
    @DisplayName("기본 일곱은 system_type 을 든다 — 이게 없으면 옛 기록이 안 세어진다")
    void theDefaultsCarryTheirSystemType() throws Exception {
        Account mom = account("엄마");

        long groupId = createGroup(mom);

        assertThat(careItems.listOf(groupId))
                .allSatisfy(item -> assertThat(item.getSystemType())
                        .as("%s 가 system_type 을 안 들면 옛 care_log 를 못 센다", item.getName())
                        .isNotNull());
    }

    @Test
    @DisplayName("집마다 제 목록이다 — 옆집 항목이 섞이면 안 된다")
    void eachHouseHasItsOwnList() throws Exception {
        Account mom = account("엄마");
        Account neighbour = account("이웃");

        long ours = createGroup(mom);
        long theirs = createGroup(neighbour);

        assertThat(ours).isNotEqualTo(theirs);
        assertThat(careItems.listOf(ours)).hasSize(7);
        assertThat(careItems.listOf(theirs)).hasSize(7);
        assertThat(careItems.listOf(ours))
                .extracting(CareItem::getId)
                .doesNotContainAnyElementsOf(
                        careItems.listOf(theirs).stream().map(CareItem::getId).toList());
    }

    @Test
    @DisplayName("접힌 것도 목록에 온다 — 고치기 화면이 '다시 켜기' 를 그리려면 봐야 한다")
    void archivedItemsStayInTheList() throws Exception {
        Account mom = account("엄마");
        long groupId = createGroup(mom);
        List<CareItem> before = careItems.listOf(groupId);

        // 조각 2 의 API 가 할 일을 여기서는 직접 한다 — 이 테스트가 재는 것은 조회다.
        archive(before.get(3).getId());

        assertThat(careItems.listOf(groupId))
                .as("접힌 것을 빼면 다시 켤 방법이 화면에서 사라진다")
                .hasSize(7);
    }

    // ─────────────────────────── 지그 ───────────────────────────

    @Autowired
    private com.heattrip.heat_trip_backend.care.repository.CareItemRepository repository;

    private void archive(long itemId) {
        CareItem item = repository.findById(itemId).orElseThrow();
        repository.save(CareItem.builder()
                .id(item.getId())
                .group(item.getGroup())
                .dog(item.getDog())
                .name(item.getName())
                .icon(item.getIcon())
                .systemType(item.getSystemType())
                .dailyTarget(item.getDailyTarget())
                .sortOrder(item.getSortOrder())
                .archivedAt(com.heattrip.heat_trip_backend.care.CareTime.nowUtc())
                .createdAt(item.getCreatedAt())
                .build());
    }

    private record Account(long id, String token) { }

    private Account account(String nickname) {
        long serial = SEQUENCE.incrementAndGet();
        User user = users.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("careitem-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name(nickname)
                .nickname(nickname)
                .build());
        return new Account(user.getId(), jwtProvider.createAccessToken(user.getId(), user.getRole()));
    }

    private long createGroup(Account owner) throws Exception {
        return body(mockMvc.perform(post("/api/groups")
                        .header("Authorization", "Bearer " + owner.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"보리네\"}"))
                .andExpect(status().isCreated())).path("id").asLong();
    }

    private JsonNode body(ResultActions actions) throws Exception {
        MockHttpServletResponse response = actions.andReturn().getResponse();
        return objectMapper.readTree(response.getContentAsString(StandardCharsets.UTF_8));
    }
}
