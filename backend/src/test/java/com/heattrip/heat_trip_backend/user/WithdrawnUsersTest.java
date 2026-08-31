package com.heattrip.heat_trip_backend.user;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.heattrip.heat_trip_backend.user.repository.UserRepository;
import java.util.Arrays;
import java.util.Collection;
import java.util.List;
import java.util.Set;
import java.util.stream.IntStream;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * 탈퇴자 가려내기. (이슈 #82 완료 조건 8)
 *
 * <p>여기가 지키는 것은 <b>"몇 명이든 쿼리 한 번"</b> 이다. 커뮤니티 카드 목록은 한 번에 최대
 * 100건이고({@code SocialService.MAX_LIMIT}), id 마다 따로 물으면 쿼리가 100개가 된다.
 * 그 서비스는 리액션과 댓글 수에서 이미 같은 함정을 피해 뒀다 — 여기서 그것을 깨면 안 된다.
 */
@ExtendWith(MockitoExtension.class)
class WithdrawnUsersTest {

    @Mock
    private UserRepository users;

    private WithdrawnUsers withdrawnUsers() {
        return new WithdrawnUsers(users);
    }

    @Test
    @DisplayName("살아 있는 id 는 빠지고 없는 id 만 남는다")
    void returnsOnlyTheIdsThatAreGone() {
        when(users.findExistingIds(any())).thenReturn(List.of(1L, 3L));

        Set<Long> gone = withdrawnUsers().among(List.of(1L, 2L, 3L, 4L));

        assertThat(gone).containsExactlyInAnyOrder(2L, 4L);
    }

    @Test
    @DisplayName("id 가 백 개여도 쿼리는 한 번이다 — 이게 이 클래스의 존재 이유다")
    void asksOnceRegardlessOfHowManyIds() {
        when(users.findExistingIds(any())).thenReturn(List.of());
        List<Long> hundred = IntStream.rangeClosed(1, 100).mapToObj(Long::valueOf).toList();

        withdrawnUsers().among(hundred);

        ArgumentCaptor<Collection<Long>> asked = ArgumentCaptor.forClass(Collection.class);
        verify(users, times(1)).findExistingIds(asked.capture());

        assertThat(asked.getValue())
                .as("""
                        id 마다 물으면 카드 100건 조회에 쿼리가 100개 붙는다. 한 번에 물어야 한다.

                        SocialService 는 리액션과 댓글 수에서 이미 이 함정을 피해 뒀다 —
                        탈퇴자 조회가 그것을 깨면 안 된다.
                        """)
                .hasSize(100);
    }

    @Test
    @DisplayName("물어볼 것이 없으면 쿼리를 아예 안 보낸다")
    void doesNotQueryWhenThereIsNothingToAsk() {
        assertThat(withdrawnUsers().among(List.of())).isEmpty();

        verify(users, never()).findExistingIds(any());
    }

    @Test
    @DisplayName("null id 는 묻지 않는다 — 로그인 없이 남긴 글은 탈퇴가 아니라 처음부터 익명이다")
    void nullIdsAreNotAsked() {
        when(users.findExistingIds(any())).thenReturn(List.of(7L));

        Set<Long> gone = withdrawnUsers().among(Arrays.asList(7L, null, null));

        assertThat(gone)
                .as("null 은 탈퇴자가 아니다. 여기 섞이면 앱이 익명 글을 알 수 없음으로 그린다")
                .isEmpty();
    }

    @Test
    @DisplayName("null 만 있으면 쿼리를 안 보낸다")
    void onlyNullsMeanNoQuery() {
        assertThat(withdrawnUsers().among(Arrays.asList(null, null))).isEmpty();

        verify(users, never()).findExistingIds(any());
    }

    @Test
    @DisplayName("같은 id 가 여러 번 와도 한 번만 묻는다 — 한 사람이 카드를 여럿 쓸 수 있다")
    void duplicateIdsAreAskedOnce() {
        when(users.findExistingIds(any())).thenReturn(List.of());

        withdrawnUsers().among(List.of(5L, 5L, 5L, 6L));

        ArgumentCaptor<Collection<Long>> asked = ArgumentCaptor.forClass(Collection.class);
        verify(users).findExistingIds(asked.capture());

        assertThat(asked.getValue()).hasSize(2);
    }
}
