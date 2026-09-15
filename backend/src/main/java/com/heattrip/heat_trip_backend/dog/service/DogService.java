package com.heattrip.heat_trip_backend.dog.service;

import com.heattrip.heat_trip_backend.dog.DogTime;
import com.heattrip.heat_trip_backend.dog.DogOwnership;
import com.heattrip.heat_trip_backend.dog.DogProfileView;
import com.heattrip.heat_trip_backend.dog.dto.DogRequest;
import com.heattrip.heat_trip_backend.dog.dto.DogPatchRequest;
import com.heattrip.heat_trip_backend.dog.dto.DogResponse;
import com.heattrip.heat_trip_backend.dog.entity.Dog;
import com.heattrip.heat_trip_backend.dog.entity.DogSize;
import com.heattrip.heat_trip_backend.dog.entity.PetSpecies;
import com.heattrip.heat_trip_backend.group.FamilyMembership;
import com.heattrip.heat_trip_backend.dog.repository.DogRepository;
import com.heattrip.heat_trip_backend.S3.MediaAttachment;
import com.heattrip.heat_trip_backend.user.entity.User;

import lombok.RequiredArgsConstructor;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.Clock;
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
 *
 * <h2>삭제는 소프트 삭제다 (#156)</h2>
 * <p>{@link #delete} 는 {@code deleted_at} 을 찍을 뿐 행을 지우지 않는다 — 이유는 {@link Dog} 의
 * javadoc(산책 CASCADE). 지운 뒤에는 세 조회 전부에서 사라지고, 같은 id 로 다시 부르면 404 다.
 * 지운 아이는 {@value #MAX_PETS} 상한에 세지 않는다 — 보낸 아이 때문에 새 아이를 못 들이면
 * 안 된다. 되살리기는 두지 않는다 — 그래서 앱의 확인 문구가 그만큼 분명해야 한다.
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

    /** "우리 집 식구는 누구인가" — group 모듈의 공개 표면. 멤버십 원본은 chat_room_member 다. */
    private final FamilyMembership family;

    /** 프로필 사진 (#448). 모듈 경계의 공개 타입만 든다 — {@code S3.media.MediaService} 는 안 든다. */
    private final MediaAttachment media;

    /** 삭제 시각. 빈은 {@code Asia/Seoul} 이지만 저장값은 UTC 로 눕힌다(계약: 표에 담기는 값은 UTC). */
    private final Clock clock;

    public List<DogResponse> mine(Long userId) {
        return dogs.findMine(userId).stream().map(this::toResponse).toList();
    }

    /**
     * {@inheritDoc}
     *
     * <p>집 아이 목록을 한 번 읽어 그 안에 있는지 본다. 목록이 길어야 열 마리 남짓이라
     * 전용 쿼리를 따로 두지 않는다 — 두면 "집 아이" 의 정의가 두 벌이 된다.
     */
    @Override
    public Dog requireInFamilyEntity(long groupId, Long dogId) {
        if (dogId == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "어느 아이인지 알려 주세요.");
        }
        return dogs.findOfUsers(family.memberUserIds(groupId)).stream()
                .filter(dog -> dog.getId().equals(dogId))
                .findFirst()
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.BAD_REQUEST, "우리 집 아이가 아닙니다."));
    }

    /** {@inheritDoc} */
    @Override
    public Dog requireInHouseholdEntity(long actorUserId, Long dogId) {
        if (dogId == null) {
            throw notFound();
        }
        return dogs.findOfUsers(family.householdUserIds(actorUserId)).stream()
                .filter(dog -> dog.getId().equals(dogId))
                .findFirst()
                .orElseThrow(DogService::notFound);
    }

    /** {@inheritDoc} */
    @Override
    public void requireInHousehold(long actorUserId, long dogId) {
        requireInHouseholdEntity(actorUserId, dogId);
    }

    /** 남의 것과 없는 것이 같은 404 다 — id 를 훑어 남의 마릿수를 세지 못하게. */
    private static ResponseStatusException notFound() {
        return new ResponseStatusException(HttpStatus.NOT_FOUND, "반려동물을 찾을 수 없습니다.");
    }

    /**
     * <b>우리 집 아이</b> — 그 가족의 식구들이 등록한 아이 전부. 이슈 #563.
     *
     * <h2>왜 이 경로가 있나</h2>
     *
     * <p>이 앱의 목적은 업무 분담과 누락 방지다(#76). 그런데 아이가 <b>사람 것</b>이라,
     * 엄마가 보리를 등록하고 아빠가 가족에 들어오면 아빠 홈은 "아직 등록된 아이가 없어요"
     * 였다. 아빠가 보리를 또 등록하면 같은 아이가 두 마리가 되고 케어 기록이 둘로 갈린다.
     *
     * <p><b>표를 안 바꾼다.</b> 아이의 주인은 그대로 등록한 사람이고, 여기서 식구 목록으로
     * 파생한다 — 가족에 들어오는 순간 보이고 나가는 순간 빠진다. 옮기는 코드도 되돌리는
     * 코드도 없다({@code FamilyMembership} javadoc).
     *
     * <p><b>공유되는 것은 돌봄이지 소유가 아니다.</b> {@code PATCH}·{@code DELETE}·상세는
     * 그대로 등록한 사람만이고 남의 것은 404 다.
     *
     * @throws org.springframework.web.server.ResponseStatusException 그 가족의 식구가 아니면 403
     */
    public List<DogResponse> ofFamily(long groupId, long actorUserId) {
        family.requireMember(groupId, actorUserId);
        // 요청자가 그 방의 살아 있는 멤버라는 것을 방금 확인했으므로 목록은 비지 않는다 —
        // 빈 목록 가드를 두지 않는 이유다(`in ()` 은 DB 마다 다르게 죽지만 여기 도달할 수 없다).
        return dogs.findOfUsers(family.memberUserIds(groupId)).stream()
                // 남이 등록한 아이는 mine=false 다(#563). 앱이 이 값으로 "고칠 수 있나" 를 가른다 —
                // 없으면 아빠가 보리를 고르고 "우리 아이 정보 관리" 를 눌렀을 때 그제서야 404 다.
                .map(dog -> toResponse(dog, dog.isOwnedBy(actorUserId)))
                .toList();
    }

    /**
     * {@inheritDoc}
     *
     * <p><b>집 기준이다</b>(#563). 이 값을 읽는 곳은 주간 통계 하나뿐인데
     * ({@code GET /api/walks/stats/weekly} → {@code WeeklyInsightService.attach}) 그 통계는 이미
     * <b>집</b> 산책을 센다. 여기만 "내가 등록한 아이인가" 로 두면 판정 둘이 어긋나고,
     * 아빠가 엄마의 보리를 고르는 순간 <b>통계 응답 전체가 404</b> 가 된다 — 실제로 그랬다.
     * 목록({@code GET /api/walks})은 집 기준이라 초록이었던 탓에 조각 3 의 테스트를 다 지나갔다.
     *
     * <p>아이를 안 고른 경우도 집에서 고른다. 그쪽 통계가 집 전체라서이기도 하고, 자기 아이
     * 없이 배우자의 아이만 있는 집에서 프로필이 통째로 {@code null} 이 되기 때문이다.
     */
    @Override
    public DogProfileView profileOf(long userId, Long dogId) {
        Dog dog = dogId != null
                ? requireInHouseholdEntity(userId, dogId)
                : dogs.findOfUsers(family.householdUserIds(userId)).stream().findFirst().orElse(null);
        if (dog == null) {
            return null;
        }
        return new DogProfileView(dog.getSize().wire(), toResponse(dog).ageMonths());
    }

    public DogResponse one(Long userId, long dogId) {
        return toResponse(require(userId, dogId));
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

        return toResponse(dogs.save(dog));
    }

    /**
     * 부분 수정 — 이슈 #516. <b>보낸 것만</b> 바꾸고 안 보낸 것은 그대로 둔다.
     *
     * <p>2026-09-15 이전에는 이 경로가 없었고, 앱의 편집 화면은 메모리의 목록만 바꾼 뒤
     * <b>"이 기기에만 반영했어요"</b> 라고 말했다. 그 말도 사실이 아니었다 — 기기에도 안
     * 남아서, 앱을 껐다 켜면 {@code PetSync.load()} 가 서버 목록으로 통째로 갈아끼웠다.
     *
     * <p>남의 것과 없는 것은 같은 <b>404</b> 다(ADR-0017 규약 3). 빈 본문은 <b>400</b> 이다 —
     * 계약의 {@code minProperties: 1} 이고, 200 으로 받으면 "저장했어요" 를 보고 아무것도
     * 안 바뀐 화면을 보게 된다.
     */
    @Transactional
    public DogResponse patch(Long userId, long dogId, DogPatchRequest request) {
        if (request.isEmpty()) {
            throw new IllegalArgumentException("바꿀 것을 하나는 보내 주세요.");
        }
        // 계약 밖의 값이면 여기서 400 이다. 엔티티를 찾기 **전에** 판정한다 — 남의 id 로
        // 틀린 값을 보냈을 때 400 과 404 중 어느 쪽이 먼저인지가 흔들리면 안 된다.
        PetSpecies species = request.speciesOrNull();
        DogSize size = request.sizeOrNull();
        if (request.isBirthGiven() && request.getBirth() != null
                && request.getBirth().isAfter(LocalDate.now(clock))) {
            throw new IllegalArgumentException("생일은 미래일 수 없습니다.");
        }
        if (request.getName() != null && request.getName().isBlank()) {
            throw new IllegalArgumentException("이름을 입력해 주세요.");
        }

        Dog dog = require(userId, dogId);
        if (request.getName() != null) {
            dog.rename(request.getName().strip());
        }
        if (species != null) {
            dog.changeSpecies(species);
        }
        if (request.getBreed() != null) {
            dog.changeBreed(blankToNull(request.getBreed()));
        }
        if (size != null) {
            dog.changeSize(size);
        }
        if (request.isBirthGiven()) {
            dog.changeBirth(request.getBirth());
        }
        if (request.getNeutered() != null) {
            dog.changeNeutered(request.getNeutered());
        }
        return toResponse(dogs.save(dog));
    }

    // ─────────────────────────── 프로필 사진 (#448) ───────────────────────────

    /**
     * 프로필 사진을 붙인다 — 앱이 {@code POST /media}(PROFILE_IMAGE) 로 올린 미디어의 id 를 받는다.
     * 한 아이에 한 장이라 <b>갈아 끼우기</b>다: 새 것을 먼저 붙이고 옛 것을 지운다
     * ({@link MediaAttachment#replace} — 지우기는 S3 를 부르므로 붙이기가 먼저다).
     * 남의 미디어 · 아직 안 올라온 것 · 이미 다른 데 붙은 것은 붙이기가 400 으로 거절한다.
     */
    @Transactional
    public DogResponse updateAvatar(Long userId, long dogId, long mediaId) {
        require(userId, dogId);
        List<MediaAttachment.AttachedMedia> attached = media.replace(
                MediaAttachment.REF_DOG, String.valueOf(dogId), List.of(mediaId), userId);
        // 붙이기의 조건부 UPDATE 가 영속성 컨텍스트를 비운다(clearAutomatically) — 그 전에 읽은 엔티티는
        // 떨어져 나가 고쳐도 안 남는다. 그래서 붙인 **뒤에** 다시 읽는다.
        Dog dog = require(userId, dogId);
        if (attached.size() != 1 || attached.get(0).kind() != MediaAttachment.Kind.IMAGE) {
            throw new IllegalArgumentException("프로필 사진은 사진 한 장이어야 합니다.");
        }
        dog.changeAvatar(attached.get(0).key());
        return toResponse(dog);
    }

    /** 프로필 사진을 뗀다 — 파일도 지운다. 없는데 떼도 200 이다(멱등). */
    @Transactional
    public DogResponse removeAvatar(Long userId, long dogId) {
        require(userId, dogId);
        media.detachAll(MediaAttachment.REF_DOG, String.valueOf(dogId));
        Dog dog = require(userId, dogId); // 떼기가 컨텍스트를 비울 수 있다 — updateAvatar 와 같은 이유
        dog.changeAvatar(null);
        return toResponse(dog);
    }

    private DogResponse toResponse(Dog dog) {
        return toResponse(dog, true);
    }

    /** {@code mine} 은 집 아이 목록에서만 {@code false} 가 될 수 있다(#563). */
    private DogResponse toResponse(Dog dog, boolean mine) {
        return DogResponse.of(
                dog, dog.getAvatar() == null ? null : media.publicUrl(dog.getAvatar()), mine);
    }

    /**
     * 소프트 삭제 — 클래스 javadoc. 남의 것·없는 것·이미 지운 것은 전부 같은 404 다
     * ({@code findMineById} 가 셋을 구분하지 않는다).
     *
     * @throws ResponseStatusException 404
     */
    @Transactional
    public void delete(Long userId, long dogId) {
        require(userId, dogId);
        // 되살리기가 없는 소프트 삭제다 — 사진 파일을 남겨 둘 이유가 없다(#448). 떼기가 영속성
        // 컨텍스트를 비울 수 있어 **먼저** 떼고 그 뒤에 읽어 표시한다.
        media.detachAll(MediaAttachment.REF_DOG, String.valueOf(dogId));
        Dog dog = require(userId, dogId);
        dog.markDeleted(DogTime.nowUtc(clock));
        dog.changeAvatar(null);
    }

    /**
     * 우리 집 아이 id 전부 — 이슈 #418, #563 이 집 기준으로 넓혔다.
     * 이유는 {@link DogOwnership#householdDogIds} 에 적었다.
     *
     * <p>{@code findOfUsers} 를 그대로 쓴다 — 지운 아이를 거르는 규칙({@code deleted_at is null},
     * #156)이 그 쿼리 안에 있어서, 여기서 다시 적으면 두 곳이 된다.
     */
    @Override
    @Transactional(readOnly = true)
    public java.util.List<Long> householdDogIds(long actorUserId) {
        return dogs.findOfUsers(family.householdUserIds(actorUserId)).stream()
                .map(Dog::getId)
                .toList();
    }

    /**
     * 조회 + <b>등록한 사람인가</b>. 이 판정은 모듈 밖으로 안 나간다(#563) —
     * 아이 정보를 고치고 지우는 일만 "등록한 사람만" 이고, 나머지는 집 기준이다.
     */
    private Dog require(Long userId, long dogId) {
        return dogs.findMineById(dogId, userId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND));
    }

    /** 빈 문자열은 {@code null} 이다 — "품종을 모른다" 와 "빈 문자열이다" 를 나누지 않는다. */
    private static String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value.strip();
    }
}
