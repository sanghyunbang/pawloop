package com.heattrip.heat_trip_backend.dog.dto;

import com.heattrip.heat_trip_backend.dog.entity.DogSize;
import com.heattrip.heat_trip_backend.dog.entity.PetSpecies;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.time.LocalDate;

/**
 * 계약의 {@code DogInput} — 이슈 #145.
 *
 * <h2>{@code species}·{@code size} 를 enum 이 아니라 {@code String} 으로 받는다</h2>
 * <p>{@code CareLogRequest} 는 {@code CareType} 을 직접 받는다. 여기가 다른 이유가 있다.
 *
 * <p>enum 으로 받으면 잘못된 값이 <b>역직렬화 중에</b> 터지고, Jackson 이 그것을
 * {@code HttpMessageNotReadableException} 으로 싼다. 그러면 전역 처리기가
 * <b>"요청 본문을 읽을 수 없습니다."</b> 하나로 답한다 — 처리기가 {@code ex.getMessage()} 를
 * 일부러 싣지 않기 때문이다(#6: 그 메시지에 입력값이 그대로 섞여 있다).
 *
 * <p>문제는 그러면 <b>같은 필드가 두 얼굴</b>이 된다는 것이다. {@code size} 를
 * <b>안 보내면</b> {@code null} 이 서비스까지 도달해 "몸집은 small · medium · large 중
 * 하나여야 합니다" 가 나가고, <b>틀린 값</b>을 보내면 "요청 본문을 읽을 수 없습니다" 가
 * 나간다. 같은 실수에 다른 답을 주는 셈이다.
 *
 * <p>{@code String} 으로 받아 서비스에서 옮기면 둘이 같은 문구를 받는다. 그리고 그 문구는
 * <b>허용 목록만</b> 담는다 — 계약에 이미 공개된 값이라 실어도 되고, 입력값은 안 싣는다.
 *
 * @param birth 미래 날짜는 400 이다. {@code @PastOrPresent} 를 쓰지 않는 이유는 기본 메시지가
 *              영어이고 그 문구가 그대로 응답 본문이 되기 때문이다.
 */
public record DogRequest(
        @NotBlank(message = "이름을 입력해 주세요.")
        @Size(max = 50, message = "이름은 50자를 넘을 수 없습니다.")
        String name,

        String species,

        @Size(max = 50, message = "품종은 50자를 넘을 수 없습니다.")
        String breed,

        String size,

        LocalDate birth,

        Boolean neutered,

        /**
         * 사진이 없을 때의 얼굴 — 이슈 #585. <b>선택</b>이다.
         *
         * <p>안 보내면 {@code null} 이고 앱이 종류 기본 그림을 쓴다. 목록 밖이면 400 이다
         * ({@link com.heattrip.heat_trip_backend.dog.entity.PetCharacter#of}).
         */
        String character) {

    /** 계약이 {@code default: dog} 로 선언했다. 값이 계약 밖이면 400 이다. */
    public PetSpecies speciesOrDefault() {
        return PetSpecies.of(species);
    }

    /** 계약이 {@code required} 로 선언했다. 없어도 틀려도 <b>같은 문구</b>로 400 이다. */
    public DogSize requireSize() {
        return DogSize.of(size);
    }

    /** 계약이 {@code default: false} 로 선언했다. 보내지 않으면 중성화 안 함이다. */
    public boolean neuteredOrDefault() {
        return neutered != null && neutered;
    }
}
