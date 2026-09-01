package com.heattrip.heat_trip_backend.dog.dto;

import com.heattrip.heat_trip_backend.dog.entity.Dog;
import com.heattrip.heat_trip_backend.dog.entity.DogSize;
import com.heattrip.heat_trip_backend.dog.entity.PetSpecies;

import java.time.LocalDate;
import java.time.Period;

/**
 * 계약의 {@code Dog} — 이슈 #145.
 *
 * @param ageMonths <b>파생값이다.</b> 저장하지 않는다 — 저장하는 순간 낡는다.
 *                  {@code birth} 가 없으면 {@code null} 이고 0 이 아니다. 0 은 "갓 태어났다"
 *                  라는 <b>다른 뜻</b>이라, 모르는 것을 0 으로 눕히면 화면이 거짓말을 한다.
 * @param avatarUrl #145 는 업로드를 구현하지 않으므로 <b>항상 {@code null}</b> 이다.
 */
public record DogResponse(
        Long id,
        String name,
        PetSpecies species,
        String breed,
        DogSize size,
        LocalDate birth,
        Integer ageMonths,
        boolean neutered,
        String avatarUrl) {

    public static DogResponse of(Dog dog) {
        return new DogResponse(
                dog.getId(),
                dog.getName(),
                dog.getSpecies(),
                dog.getBreed(),
                dog.getSize(),
                dog.getBirth(),
                ageMonths(dog.getBirth()),
                dog.isNeutered(),
                dog.getAvatar());
    }

    /**
     * 생일에서 개월 수를 낸다.
     *
     * <p><b>미래 생일은 {@code null} 이다.</b> {@code Period} 는 음수를 그대로 주는데,
     * "-3개월" 을 화면에 그리면 그 자체가 버그로 보인다. 애초에 미래 생일을 저장하지 않는
     * 것이 맞지만, 이미 들어온 값에 대해서도 화면이 이상해지지 않게 한다.
     */
    static Integer ageMonths(LocalDate birth) {
        if (birth == null) {
            return null;
        }
        LocalDate today = LocalDate.now();
        if (birth.isAfter(today)) {
            return null;
        }
        return (int) Period.between(birth, today).toTotalMonths();
    }
}
