package com.heattrip.heat_trip_backend.dog.service;

import com.heattrip.heat_trip_backend.dog.DogOwnership;
import com.heattrip.heat_trip_backend.dog.dto.DogRequest;
import com.heattrip.heat_trip_backend.dog.dto.DogResponse;
import com.heattrip.heat_trip_backend.dog.entity.Dog;
import com.heattrip.heat_trip_backend.dog.entity.DogSize;
import com.heattrip.heat_trip_backend.dog.entity.PetSpecies;
import com.heattrip.heat_trip_backend.dog.repository.DogRepository;
import com.heattrip.heat_trip_backend.user.entity.User;

import lombok.RequiredArgsConstructor;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;
import java.util.List;

/**
 * 반려동물 프로필 — 이슈 #145.
 *
 * <h2>없는 것과 남의 것을 구분하지 않는다</h2>
 * <p>{@code dogs.md} 는 타인 리소스를 403 으로 적어 뒀지만 <b>404 로 간다.</b> 403 은
 * "그 id 는 존재한다" 를 알려 주는 셈이라, id 를 훑으면 남이 반려동물을 몇 마리 키우는지
 * 셀 수 있다. 계약({@code GET /api/walks/{walkId}})이 같은 이유로 404 하나만 선언했고
 * 여기도 같은 규칙을 쓴다 — 한 저장소 안에서 규칙이 둘이면 어느 쪽이 정본인지 매번 묻게 된다.
 *
 * <p>그래서 {@code findMineById} 가 소유자 조건을 <b>쿼리 안</b>에 담는다. 서비스에 분기가
 * 없으면 그 분기가 응답 코드로 샐 일도 없다.
 *
 * <h2>상한이 있다</h2>
 * <p>한 계정이 등록할 수 있는 수를 {@value #MAX_PETS} 로 막는다. 없으면 인증만 통과하면
 * 행을 무한히 만들 수 있고, rate limit 은 <b>속도</b>를 재지 <b>총량</b>을 재지 않는다 —
 * 하루에 조금씩 넣으면 한도에 안 걸린다.
 */
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class DogService implements DogOwnership {

    /**
     * 한 계정의 반려동물 수 상한.
     *
     * <p>20 은 <b>관측이 아니다.</b> 다견·다묘 가정을 넉넉히 덮으면서 목록 응답이 한 화면에
     * 들어오는 범위로 고른 값이다. 실사용에서 막히는 사람이 나오면 올린다.
     */
    public static final int MAX_PETS = 20;

    private final DogRepository dogs;

    public List<DogResponse> mine(Long userId) {
        return dogs.findMine(userId).stream().map(DogResponse::of).toList();
    }

    public DogResponse one(Long userId, long dogId) {
        return DogResponse.of(require(userId, dogId));
    }

    @Transactional
    public DogResponse register(User owner, DogRequest request) {
        // 계약 밖의 값이면 여기서 400 이 된다. 없을 때와 틀렸을 때가 **같은 문구**를 받는
        // 이유는 DogRequest javadoc 에 있다.
        DogSize size = request.requireSize();
        PetSpecies species = request.speciesOrDefault();

        if (request.birth() != null && request.birth().isAfter(LocalDate.now())) {
            throw new IllegalArgumentException("생일은 미래일 수 없습니다.");
        }
        if (dogs.findMine(owner.getId()).size() >= MAX_PETS) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "반려동물은 " + MAX_PETS + "마리까지 등록할 수 있습니다.");
        }

        Dog dog = Dog.builder()
                .user(owner)
                .name(request.name().strip())
                .species(species)
                .breed(blankToNull(request.breed()))
                .size(size)
                .birth(request.birth())
                .neutered(request.neuteredOrDefault())
                .build();

        return DogResponse.of(dogs.save(dog));
    }

    /**
     * 내 반려동물이 맞는지 확인한다. 산책 저장이 {@code dogId} 를 받을 때 쓴다.
     *
     * <p>{@code walk} 모듈이 {@code DogRepository} 를 직접 부르지 않고 여기를 지나게 하는
     * 이유는, 소유권 판정이 두 곳에 생기면 <b>한쪽만 고쳐지는 날이 오기 때문</b>이다.
     */
    @Override
    public void requireMine(Long userId, long dogId) {
        if (!dogs.isMine(dogId, userId)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND);
        }
    }

    /**
     * 내 반려동물을 꺼낸다. 산책 저장이 {@code dogId} 를 받을 때 쓴다.
     *
     * <p>{@link #requireMine} 과 달리 <b>행을 돌려준다</b> — 산책 엔티티가
     * {@code @ManyToOne Dog} 를 들어야 {@code fk_walk_dog} 가 생기기 때문이다.
     *
     * <p>{@code walk} 모듈이 {@code DogRepository} 를 직접 부르지 않고 여기를 지나게 하는
     * 이유는 {@link #requireMine} 과 같다 — 소유권 판정이 두 곳에 생기면 <b>한쪽만 고쳐지는
     * 날이 온다.</b>
     */
    @Override
    public Dog requireMineEntity(Long userId, Long dogId) {
        if (dogId == null) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND);
        }
        return require(userId, dogId);
    }

    private Dog require(Long userId, long dogId) {
        return dogs.findMineById(dogId, userId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND));
    }

    /** 빈 문자열은 {@code null} 이다 — "품종을 모른다" 와 "빈 문자열이다" 를 나누지 않는다. */
    private static String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value.strip();
    }
}
