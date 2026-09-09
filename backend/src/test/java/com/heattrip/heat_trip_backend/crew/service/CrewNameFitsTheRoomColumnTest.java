package com.heattrip.heat_trip_backend.crew.service;

import com.heattrip.heat_trip_backend.chat.entity.ChatRoom;
import com.heattrip.heat_trip_backend.group.entity.FamilyGroup;

import jakarta.persistence.Column;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.lang.reflect.Field;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 방 이름을 만드는 도메인들의 길이 한도가 <b>컬럼보다 짧은가</b> — 이슈 #417.
 *
 * <h2>왜 이 검사가 따로 있어야 하는가</h2>
 * <p>{@code ChatRoomService.renameRoom} 은 길이를 <b>안 잰다</b>. 재려면 컬럼 길이를 숫자로
 * 적어야 하는데, chat main 소스에 그런 숫자를 두는 것을 {@code ChatLimitsTest} 가 막는다 —
 * 한도는 {@code FixedChatLimits} 한 곳에 살아야 하기 때문이다. 실제로 그 테스트가 처음 쓴
 * {@code MAX_NAME_LENGTH = 50} 을 잡았다.
 *
 * <p>그래서 길이는 <b>부르는 쪽의 규칙</b>이 됐다. 그 대신 여기서 관계를 잰다 — 부르는 쪽의
 * 한도가 컬럼을 넘으면 그 이름은 저장 시점에 터지고 <b>500</b> 이 나간다. 화면에는 "잠시 후
 * 다시 시도해 주세요" 만 뜨고, 사용자는 자기 이름의 무엇이 문제인지 영원히 모른다.
 *
 * <p>컬럼 길이를 여기 숫자로 안 적고 <b>애너테이션에서 읽는</b> 것이 요점이다. 적어 두면 그
 * 값이 낡는 날 이 검사가 통과하면서 틀린다 — 재려던 것이 정확히 "두 숫자가 어긋났는가" 인데
 * 그 둘 중 하나를 베껴 오면 잴 것이 없어진다.
 *
 * <p>스프링을 안 띄운다(#21).
 */
class CrewNameFitsTheRoomColumnTest {

    @Test
    @DisplayName("크루 이름 한도가 chat_room.name 컬럼보다 짧다")
    void theCrewNameLimitFitsTheRoomNameColumn() throws Exception {
        int column = roomNameColumnLength();

        assertThat(CrewService.MAX_NAME_LENGTH)
                .as("""
                        넘으면 저장 시점에 터져 500 이 나간다 — 화면은 "잠시 후 다시" 만 \
                        말하고 사용자는 이름의 무엇이 문제인지 모른다. chat 은 이 길이를 \
                        못 잰다(클래스 javadoc).""")
                .isLessThanOrEqualTo(column);
    }

    @Test
    @DisplayName("가족 그룹 이름 한도도 같은 컬럼에 들어간다 — 방 이름을 만드는 도메인이 둘이다")
    void theFamilyGroupNameLimitFitsTooSoTheRuleIsNotCrewOnly() throws Exception {
        Field name = FamilyGroup.class.getDeclaredField("name");
        Column column = name.getAnnotation(Column.class);

        assertThat(column)
                .as("family_group.name 에 @Column 이 없으면 이 검사는 아무것도 안 지킨다")
                .isNotNull();
        assertThat(column.length())
                .as("방 이름을 만드는 도메인이 둘이라, 한쪽만 재면 다른 쪽이 조용히 새어 나간다")
                .isLessThanOrEqualTo(roomNameColumnLength());
    }

    /** {@code chat_room.name} 의 길이를 <b>애너테이션에서</b> 읽는다 — 클래스 javadoc 참조. */
    private static int roomNameColumnLength() throws NoSuchFieldException {
        Column column = ChatRoom.class.getDeclaredField("name").getAnnotation(Column.class);

        assertThat(column)
                .as("chat_room.name 에 @Column 이 없다 — 컬럼을 옮겼다면 이 검사도 함께 고친다")
                .isNotNull();
        return column.length();
    }
}
