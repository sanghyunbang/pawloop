package com.heattrip.heat_trip_backend.tour.util;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.assertThat;

public class SanitizersTest {

    @Test
    @DisplayName("truncate는 maxLen을 초과한 문자열을 자른다")
    void truncateCutsLongString() {
        String value = "abcdef";

        String result = Sanitizers.truncate(value, 3);

        assertThat(result).isEqualTo("abc");
    }

    @Test
    @DisplayName("truncate는 null을 null로 유지한다")
    void truncateKeepsNull() {
        assertThat(Sanitizers.truncate(null, 10)).isNull();
    }

    @Test
    @DisplayName("cleanTel은 허용되지 않은 문자를 제거하고 길이를 제한한다")
    void cleanTelRemovesInvalidChars() {
        String value = "TEL: 123-456-7890 abc !!!";

        String result = Sanitizers.cleanTel(value, 20);

        assertThat(result).isEqualTo("123-456-7890");
    }

}
