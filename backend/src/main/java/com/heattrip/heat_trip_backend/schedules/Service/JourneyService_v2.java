package com.heattrip.heat_trip_backend.schedules.Service;

import java.util.List;
import java.util.Optional;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.heattrip.heat_trip_backend.schedules.DTO.JourneyRequestDto;
import com.heattrip.heat_trip_backend.schedules.entity.Journey;
import com.heattrip.heat_trip_backend.schedules.entity.Schedule;
import com.heattrip.heat_trip_backend.schedules.repository.JourneyRepository_v2; // ✅ v2 리포지토리
import com.heattrip.heat_trip_backend.schedules.repository.ScheduleRepository;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

@Service
@Transactional(readOnly = true)
public class JourneyService_v2 {

    private final JourneyRepository_v2 journeyRepo; // ✅ 타입 교체
    private final UserRepository userRepo;
    private final ScheduleRepository scheduleRepo;

    public JourneyService_v2(
            JourneyRepository_v2 journeyRepo,  // ✅ 타입 교체
            UserRepository userRepo,
            ScheduleRepository scheduleRepo
    ) {
        this.journeyRepo = journeyRepo;
        this.userRepo = userRepo;
        this.scheduleRepo = scheduleRepo;
    }

    /** R: 유저별 여정 목록 */
    public List<Journey> getJourneysByUser(User user) {
        return journeyRepo.findByUser(user);
    }

    /** R: ID로 단건 조회 */
    public Optional<Journey> findById(Long id) {
        return journeyRepo.findById(id); // JpaRepository 기본 제공
    }

    /** C: 여정 생성 */
    @Transactional
    public Journey saveJourney(JourneyRequestDto dto, User user) {
        Schedule schedule = null;
        if (dto.getScheduleId() != null) {
            schedule = scheduleRepo.findById(dto.getScheduleId()).orElse(null);
        }

        Journey journey = Journey.builder()
                .user(user)
                .schedule(schedule)
                .title(dto.getTitle())
                .date(dto.getDate())
                .location(dto.getLocation())
                .weatherLabel(dto.getWeatherLabel())
                .moodLabel(dto.getMoodLabel())
                .body(dto.getBody())
                .placeId(dto.getPlaceId())  // nullable: 추천 장소에서 기록한 경우에만 채워짐
                .photos(dto.getPhotos())
                .build();

        return journeyRepo.save(journey);
    }

    /** U: 여정 수정 (null이 아닌 필드만 갱신) */
    @Transactional
    public Journey updateJourney(Journey target, JourneyRequestDto dto) {
        if (dto.getTitle() != null)        target.setTitle(dto.getTitle());
        if (dto.getDate() != null)         target.setDate(dto.getDate());
        if (dto.getLocation() != null)     target.setLocation(dto.getLocation());
        if (dto.getWeatherLabel() != null) target.setWeatherLabel(dto.getWeatherLabel());
        if (dto.getMoodLabel() != null)    target.setMoodLabel(dto.getMoodLabel());
        if (dto.getBody() != null)         target.setBody(dto.getBody());
        if (dto.getPlaceId() != null)      target.setPlaceId(dto.getPlaceId());
        if (dto.getPhotos() != null)       target.setPhotos(dto.getPhotos());

        if (dto.getScheduleId() != null) {
            Schedule schedule = scheduleRepo.findById(dto.getScheduleId()).orElse(null);
            target.setSchedule(schedule);
        }
        return target; // 영속 엔티티라 트랜잭션 종료 시 반영
    }

    /** D: 여정 삭제 */
    @Transactional
    public void deleteJourney(Journey target) {
        journeyRepo.delete(target);
    }
}
