package com.heattrip.heat_trip_backend.schedules.controller;

import com.heattrip.heat_trip_backend.schedules.entity.Schedule;
import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.schedules.DTO.ScheduleResponseDto;
import com.heattrip.heat_trip_backend.schedules.Service.ScheduleService;
import com.heattrip.heat_trip_backend.user.entity.*;
import com.heattrip.heat_trip_backend.user.service.*;

import jakarta.servlet.http.HttpServletRequest;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/public")
public class ScheduleController {

    private final ScheduleService scheduleService;
    private final UserService userService;
    private final JWTProvider jwtProvider;
    
    public ScheduleController(ScheduleService scheduleService, UserService userService, JWTProvider jwtProvider) {
        this.scheduleService = scheduleService;
        this.userService = userService;
        this.jwtProvider = jwtProvider;
    }

    // --------------조회(미완성)
    @GetMapping("/schedules")
    public ResponseEntity<?> getMySchedules(HttpServletRequest request) {
        String authHeader = request.getHeader("Authorization");
        System.out.println("스케쥴 조회 리스트 호출 / authHeader : " + authHeader);

        if (authHeader == null || !authHeader.startsWith("Bearer ")) {
            return ResponseEntity.status(401).body("인증 토큰이 없습니다.");
        }

        String token = authHeader.substring(7);
        if (!jwtProvider.validateToken(token)) {
            return ResponseEntity.status(401).body("유효하지 않은 토큰입니다.");
        }

        String userId = jwtProvider.getUserIdFromToken(token);
        User user = userService.findByEmail(userId);
        if (user == null) {
            return ResponseEntity.status(404).body("사용자를 찾을 수 없습니다.");
        }

        List<Schedule> schedules = scheduleService.findByUser(user);

        List<ScheduleResponseDto> dtos = schedules.stream()
                .map(schedule -> {
                    int journeyCount = scheduleService.countJourneysBySchedule(schedule.getScheduleId());
                    return new ScheduleResponseDto(schedule, journeyCount);
                })
                .toList();

        // ✅ 디버그는 사이즈만 안전하게 출력
        System.out.println("스케쥴 DTO 개수 = " + dtos.size());

        // ✅ 빈 결과 처리 (프론트는 204 지원)
        if (dtos.isEmpty()) {
            return ResponseEntity.noContent().build(); // 204
            // 또는: return ResponseEntity.ok(dtos); // 200 + []
        }

        return ResponseEntity.ok(dtos);
    }


    // --------------등록 
    @PostMapping("/schedules")
    public ResponseEntity<?> createSchedule(@RequestBody Schedule schedule, HttpServletRequest request) {
        System.out.println("       post schedule 진입.");
        String authHeader = request.getHeader("Authorization");
        System.out.println("         authHeader 체크 : "+authHeader);

    if (authHeader == null || !authHeader.startsWith("Bearer ")) {
        return ResponseEntity.status(401).body("PostMapping schedules : 인증 토큰이 없습니다.");
    }
    String token = authHeader.substring(7); // Bearer 제거

    if (!jwtProvider.validateToken(token)) {
        return ResponseEntity.status(401).body("유효하지 않은 토큰입니다.");
    }
    String userId = jwtProvider.getUserIdFromToken(token);
    User user = userService.findByEmail(userId);
    if (user == null) {
        return ResponseEntity.status(404).body("사용자를 찾을 수 없습니다.");
    }

    // 작성자 정보 주입
    schedule.setUser(user);
        
        Schedule saved = scheduleService.save(schedule);
        return ResponseEntity.ok(saved);
    }

    // --------------유저정보[닉네임 / 본명]
//    @GetMapping("/getuser")
//    public ResponseEntity<?> getCurrentUser(HttpServletRequest request) {
//    String authHeader = request.getHeader("Authorization");
//    System.out.println("GetUser 진입");
//
//    if (authHeader == null || !authHeader.startsWith("Bearer ")) {
//        return ResponseEntity.status(401).body("getUser clss : 인증 토큰이 없습니다.");
//    }
//
//    String token = authHeader.substring(7); // "Bearer " 제거
//
//    if (!jwtProvider.validateToken(token)) {
//        return ResponseEntity.status(401).body("유효하지 않은 토큰입니다.");
//    }
//
//    String userId = jwtProvider.getUserIdFromToken(token); // subject에 저장된 값 (예: email 또는 userId)
//
//    // userService를 통해 사용자 조회
//    User user = userService.findByEmail(userId); // or findById(userId) depending on what subject stores
//
//    if (user == null) {
//        return ResponseEntity.status(404).body("사용자를 찾을 수 없습니다.");
//    }
//
//    return ResponseEntity.ok(user);
//}

// --------------수정
@PutMapping("/schedules/{scheduleId}")
public ResponseEntity<?> updateSchedule(
        @PathVariable("scheduleId") Integer scheduleId,
        @RequestBody Schedule updatedSchedule,
        HttpServletRequest request) {
            System.out.println("                  수정 메서드 진입 ");

    String authHeader = request.getHeader("Authorization");
    if (authHeader == null || !authHeader.startsWith("Bearer ")) {
        return ResponseEntity.status(401).body("인증 토큰이 없습니다.");
    }

    String token = authHeader.substring(7);
    if (!jwtProvider.validateToken(token)) {
        return ResponseEntity.status(401).body("유효하지 않은 토큰입니다.");
    }

    String userId = jwtProvider.getUserIdFromToken(token);
    User user = userService.findByEmail(userId);
    if (user == null) {
        return ResponseEntity.status(404).body("사용자를 찾을 수 없습니다.");
    }

    // 기존 스케줄 조회
    Schedule existing = scheduleService.findById(scheduleId);
    if (existing == null) {
        return ResponseEntity.status(404).body("수정할 스케줄을 찾을 수 없습니다.");
    }

    // 본인 소유 스케줄인지 확인
    if (!existing.getUser().getId().equals(user.getId())) {
        return ResponseEntity.status(403).body("본인의 스케줄만 수정할 수 있습니다.");
    }

    // 수정 필드 반영
    existing.setTitle(updatedSchedule.getTitle());
    existing.setContent(updatedSchedule.getContent());
    existing.setDateFrom(updatedSchedule.getDateFrom());
    existing.setDateTo(updatedSchedule.getDateTo());

    // 저장
    Schedule saved = scheduleService.save(existing);
    return ResponseEntity.ok(saved);
}

// --------------삭제
@DeleteMapping("/schedules/{scheduleId}")
public ResponseEntity<?> deleteSchedule(
        @PathVariable("scheduleId") Integer scheduleId,
        HttpServletRequest request) {
            System.out.println("            스케쥴 삭제 진입 ");

    String authHeader = request.getHeader("Authorization");
    if (authHeader == null || !authHeader.startsWith("Bearer ")) {
        return ResponseEntity.status(401).body("인증 토큰이 없습니다.");
    }

    String token = authHeader.substring(7);
    if (!jwtProvider.validateToken(token)) {
        return ResponseEntity.status(401).body("유효하지 않은 토큰입니다.");
    }

    String userId = jwtProvider.getUserIdFromToken(token);
    User user = userService.findByEmail(userId);
    if (user == null) {
        return ResponseEntity.status(404).body("사용자를 찾을 수 없습니다.");
    }

    Schedule existing = scheduleService.findById(scheduleId);
    if (existing == null) {
        return ResponseEntity.status(404).body("삭제할 스케줄을 찾을 수 없습니다.");
    }

    // 본인 소유 스케줄인지 확인
    if (!existing.getUser().getId().equals(user.getId())) {
        return ResponseEntity.status(403).body("본인의 스케줄만 삭제할 수 있습니다.");
    }

    scheduleService.delete(existing);

    return ResponseEntity.noContent().build();
}



}
