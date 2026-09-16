package com.heattrip.heat_trip_backend.dog.dto;

import com.heattrip.heat_trip_backend.dog.entity.DogSize;
import com.heattrip.heat_trip_backend.dog.entity.PetCharacter;
import com.heattrip.heat_trip_backend.dog.entity.PetSpecies;

import jakarta.validation.constraints.Size;

import java.time.LocalDate;

/**
 * 계약의 {@code DogPatch} — 이슈 #516.
 *
 * <h2>왜 {@code DogRequest} 를 재사용하지 않는가</h2>
 * <p>그쪽은 생성용이라 {@code name} 이 {@code @NotBlank} 다. 재사용하면
 * {@code {"neutered": true}} 하나만 보내는 것이 400 이 되어 <b>부분 수정이 계약상
 * 불가능</b>해진다. 계약도 같은 이유로 스키마를 따로 뒀다(ADR-0017 규약 4).
 *
 * <h2>"안 보냈다" 와 "null 을 보냈다" 를 가른다 — {@code birth} 와 {@code character}</h2>
 * <p>다른 필드는 {@code null} 이 "안 바꿈" 이다({@code UpdateProfileRequest} 와 같은 규칙).
 * 그런데 생일만은 <b>지우는 방법</b>이 필요하다 — 잘못 넣은 날짜를 비울 길이 없으면 그
 * 사람은 영영 틀린 나이를 본다. 계약이 {@code birth: [string, "null"]} 로 그것을 선언했다.
 *
 * <p>가르는 방법은 <b>세터가 불렸는가</b>다. Jackson 은 <b>키가 있을 때만</b> 세터를 부르므로
 * (값이 {@code null} 이어도 부른다), 세터 안에서 깃발을 세우면 셋을 나눌 수 있다:
 * 안 보냄 · {@code null} 보냄 · 값 보냄. 라이브러리를 하나 더 들이지 않고 되는 방법이다.
 *
 * <p>레코드가 아니라 클래스인 것이 그 때문이다 — 레코드는 세터를 못 가진다.
 *
 * <h2>{@code species}·{@code size} 를 {@code String} 으로 받는다</h2>
 * <p>{@code DogRequest} 의 javadoc 에 이유가 있다 — enum 으로 받으면 틀린 값이 역직렬화에서
 * 터져 <b>"요청 본문을 읽을 수 없습니다"</b> 가 나가고, 안 보냈을 때와 다른 문구가 된다.
 */
public class DogPatchRequest {

    @Size(max = 50, message = "이름은 50자를 넘을 수 없습니다.")
    private String name;

    private String species;

    @Size(max = 50, message = "품종은 50자를 넘을 수 없습니다.")
    private String breed;

    private String size;

    private LocalDate birth;

    /** {@code birth} 키가 본문에 <b>있었는가</b>. 값이 {@code null} 이어도 참이다. */
    private boolean birthGiven;

    /**
     * 사진이 없을 때의 얼굴 — 이슈 #585.
     *
     * <p>{@code birth} 와 같은 깃발을 쓰는 이유는 <b>고른 캐릭터를 도로 물릴 방법</b>이
     * 필요해서다. {@code null} 이 "안 바꿈" 이기만 하면, 한 번 고른 사람은 종류 기본 그림으로
     * 못 돌아간다.
     */
    private String character;

    /** {@code character} 키가 본문에 <b>있었는가</b>. */
    private boolean characterGiven;

    private Boolean neutered;

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public String getSpecies() {
        return species;
    }

    public void setSpecies(String species) {
        this.species = species;
    }

    public String getBreed() {
        return breed;
    }

    public void setBreed(String breed) {
        this.breed = breed;
    }

    public String getSize() {
        return size;
    }

    public void setSize(String size) {
        this.size = size;
    }

    public LocalDate getBirth() {
        return birth;
    }

    /** Jackson 이 <b>키가 있을 때만</b> 부른다 — 그래서 여기가 "보냈다" 의 유일한 근거다. */
    public void setBirth(LocalDate birth) {
        this.birth = birth;
        this.birthGiven = true;
    }

    public boolean isBirthGiven() {
        return birthGiven;
    }

    public String getCharacter() {
        return character;
    }

    /** Jackson 이 <b>키가 있을 때만</b> 부른다 — {@link #setBirth} 와 같은 규약. */
    public void setCharacter(String character) {
        this.character = character;
        this.characterGiven = true;
    }

    public boolean isCharacterGiven() {
        return characterGiven;
    }

    /**
     * 계약 밖의 값이면 400 이다. <b>{@code null} 을 보낸 것은 "지워 달라"</b> 이므로 그대로
     * 통과시킨다 — 부르는 쪽이 {@link #isCharacterGiven} 으로 먼저 가른다.
     */
    public String characterOrNull() {
        return character == null ? null : PetCharacter.of(character).wire();
    }

    public Boolean getNeutered() {
        return neutered;
    }

    public void setNeutered(Boolean neutered) {
        this.neutered = neutered;
    }

    /**
     * 바꿀 것이 하나라도 있는가. 계약의 {@code minProperties: 1} 을 서버가 지키는 자리다.
     *
     * <p>빈 본문을 200 으로 받으면 "저장했어요" 를 보고 아무것도 안 바뀐 화면을 보게 된다.
     */
    public boolean isEmpty() {
        return name == null && species == null && breed == null && size == null
                && !birthGiven && !characterGiven && neutered == null;
    }

    /** 계약 밖의 값이면 400 이다. 안 보냈으면 {@code null} 이고 그건 "안 바꿈" 이다. */
    public PetSpecies speciesOrNull() {
        return species == null ? null : PetSpecies.of(species);
    }

    /** 같은 규칙. 없을 때와 틀렸을 때가 <b>같은 문구</b>인 이유는 {@code DogRequest} javadoc. */
    public DogSize sizeOrNull() {
        return size == null ? null : DogSize.of(size);
    }
}
