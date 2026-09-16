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
 * @param avatarUrl 프로필 사진의 공개 URL (#448). 사진이 없으면 {@code null}. 저장된 것은 S3 키이고
 *                  URL 은 서비스가 {@code MediaAttachment.publicUrl} 로 조립한다 — 행에 URL 을 박지 않는다.
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
        String avatarUrl,

        /**
         * 사진이 없을 때의 얼굴 — 이슈 #585. <b>안 골랐으면 {@code null}</b> 이고, 그때 앱이
         * 종류 기본 그림을 쓴다.
         *
         * <p>{@code avatarUrl} 과 <b>함께 올 수 있다.</b> 사진이 있으면 사진이 먼저지만,
         * 사진을 지우는 날 돌아갈 자리가 이 값이다.
         *
         * <p>이 목록({@code PetCharacter})에 없는 값이 올 수도 있다 — 서버가 목록에서 뺀
         * 뒤의 옛 행이 그 자리다. 앱은 모르는 값이면 종류 기본 그림으로 떨어뜨린다.
         */
        String character,

        /**
         * <b>요청자가 등록한 아이인가</b> — 이슈 #563.
         *
         * <p>{@code GET /api/groups/&#123;id&#125;/dogs} 가 <b>남이 등록한 아이를 섞어</b> 주기
         * 시작하면서 필요해졌다. 앱은 그 목록으로 홈 히어로 · 아이 스위처 · 케어 카드를 그리는데,
         * <b>고칠 수 있는 아이와 돌보는 아이가 다르다.</b> 이 값이 없으면 아빠가 스위처에서
         * 보리를 고르고 "우리 아이 정보 관리" 를 눌렀을 때 그제서야 404 를 만난다.
         *
         * <p>주인의 {@code userId} 를 싣지 않고 <b>불리언 하나</b>인 이유: 앱이 묻는 질문이
         * "누구 것인가" 가 아니라 "내가 고칠 수 있나" 다. id 를 실으면 답하지 않은 질문에
         * 답하는 것이고, 그 값으로 남의 마릿수를 세는 길이 하나 생긴다(#209 가 404 규칙을
         * 그 이유로 정했다).
         *
         * <p>{@code GET /api/dogs} 에서는 <b>항상 {@code true}</b> 다 — 그 경로가 주는 것이
         * 내가 등록한 아이뿐이기 때문이다. 경로마다 다른 뜻이 되지 않게 그쪽에도 싣는다.
         */
        boolean mine) {

    /**
     * @param avatarUrl 이미 조립된 공개 URL. 키({@code dog.getAvatar()})를 그대로 넣으면 앱이 상대 경로를
     *                  그리려다 깨진다 — 조립은 부르는 쪽({@code DogService})의 일이다.
     */
    public static DogResponse of(Dog dog, String avatarUrl) {
        return of(dog, avatarUrl, true);
    }

    /**
     * @param mine 요청자가 등록한 아이인가. 집 아이 목록(#563)만 {@code false} 를 실을 수 있다 —
     *             {@code GET /api/dogs} 는 늘 내 것뿐이라 위 오버로드가 {@code true} 로 부른다
     */
    public static DogResponse of(Dog dog, String avatarUrl, boolean mine) {
        return new DogResponse(
                dog.getId(),
                dog.getName(),
                dog.getSpecies(),
                dog.getBreed(),
                dog.getSize(),
                dog.getBirth(),
                ageMonths(dog.getBirth()),
                dog.isNeutered(),
                avatarUrl,
                dog.getCharacterKey(),
                mine);
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
