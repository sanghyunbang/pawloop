// package com.heattrip.heat_trip_backend.schedules.controller;

// import java.util.List;
// import java.util.Map;
// import java.util.stream.Collectors;

// import org.springframework.http.MediaType;                    // ← consumes에 필요
// import org.springframework.http.ResponseEntity;
// import org.springframework.web.bind.annotation.GetMapping;
// import org.springframework.web.bind.annotation.PostMapping;
// import org.springframework.web.bind.annotation.RequestBody;
// import org.springframework.web.bind.annotation.RequestMapping;
// // import org.springframework.web.bind.annotation.RequestParam; // @RequestPart로 대체 가능
// import org.springframework.web.bind.annotation.RequestPart;  // ← multipart에 권장
// import org.springframework.web.bind.annotation.RestController;
// import org.springframework.web.multipart.MultipartFile;

// import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
// import com.heattrip.heat_trip_backend.S3.S3Service;
// import com.heattrip.heat_trip_backend.schedules.DTO.JourneyRequestDto;
// import com.heattrip.heat_trip_backend.schedules.DTO.JourneyResponseDto;
// import com.heattrip.heat_trip_backend.schedules.Service.JourneyService;
// import com.heattrip.heat_trip_backend.schedules.entity.Journey;
// import com.heattrip.heat_trip_backend.user.entity.User;
// import com.heattrip.heat_trip_backend.user.service.UserService;
// import java.util.stream.Collectors;

// import jakarta.servlet.http.HttpServletRequest;

// @RestController
// @RequestMapping("/journeys")
// public class JourneyController {
//     private final JourneyService journeyService;
//     private final JWTProvider jwtProvider;
//     private final UserService userService;
//     private final S3Service s3Service;

//     public JourneyController(JourneyService journeyService, JWTProvider jwtProvider, UserService userService, S3Service s3Service) {
//         this.journeyService = journeyService;
//         this.jwtProvider = jwtProvider;
//         this.userService = userService;
//         this.s3Service = s3Service;
//     }

//     private User getUserFromRequest(HttpServletRequest request) {
//         String authHeader = request.getHeader("Authorization");
//         if (authHeader == null || !authHeader.startsWith("Bearer ")) return null;

//         String token = authHeader.substring(7);
//         if (!jwtProvider.validateToken(token)) return null;

//         String userId = jwtProvider.getUserIdFromToken(token); // 토큰에서 e-mail(or id) 추출
//         return userService.findByEmail(userId);
//     }

//     @GetMapping("/entries")
//     public ResponseEntity<?> getMyJourneys(HttpServletRequest request) {
//         User user = getUserFromRequest(request);
//         if (user == null) return ResponseEntity.status(401).body("Unauthorized");

//         List<Journey> journeys = journeyService.getJourneysByUser(user);
//         List<JourneyResponseDto> dtos = journeys.stream()
//             .map(JourneyResponseDto::new)
//             .toList();

//         return ResponseEntity.ok(dtos);
//     }

//     @PostMapping("/entries")
//     public ResponseEntity<?> postJourney(@RequestBody JourneyRequestDto dto, HttpServletRequest request) {
//         User user = getUserFromRequest(request);
//         if (user == null) return ResponseEntity.status(401).body("Unauthorized");

//         Journey saved = journeyService.saveJourney(dto, user);
//         return ResponseEntity.ok(new JourneyResponseDto(saved));
//     }

//     @GetMapping("/stats")
//     public ResponseEntity<?> getStats(HttpServletRequest request) {
//         User user = getUserFromRequest(request);
//         if (user == null) return ResponseEntity.status(401).body("Unauthorized");

//         List<Journey> entries = journeyService.getJourneysByUser(user);
//         Map<String, Object> stats = Map.of("entryCount", entries.size());
//         return ResponseEntity.ok(stats);
//     }

//     // ─────────────────────────────────────────────────────────────
//     // 이미지 업로드 (multipart/form-data)
//     //  - @RequestPart 사용: 복합 타입/파일 받을 때 명시적이며 오류 메시지가 더 낫습니다.
//     //  - 프런트는 FormData에 'images' 필드로 여러 파일을 담아 전송합니다.
//     // ─────────────────────────────────────────────────────────────

//     // 1) DTO (S3 에 UPLOAD관련 임의 DTO)
//     public record UploadResult(
//         String fileName,
//         String contentType,
//         long size,
//         String key,
//         String url
//     ) {}
    
//     @PostMapping(path = "/entries/images", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
//     public ResponseEntity<?> uploadDiaryImages(
//         @RequestPart("images") List<MultipartFile> images,
//         HttpServletRequest request
//     ) {
//         User user = getUserFromRequest(request);
//         if (user == null) return ResponseEntity.status(401).body("Unauthorized");
//         if (images == null || images.isEmpty()) return ResponseEntity.badRequest().body("No files provided");

//         try {
//             List<UploadResult> results = images.stream()
//                 .filter(f -> !f.isEmpty())
//                 .map(f -> {
//                     String url = s3Service.uploadFile(f, user.getId().toString());
//                     //  named args 금지, 올바른 regex 사용
//                     String key = url.replaceFirst("^https?://[^/]+/", "");
//                     return new UploadResult(
//                         f.getOriginalFilename(),
//                         f.getContentType(),
//                         f.getSize(),
//                         key,
//                         url
//                     );
//                 })
//                 .collect(Collectors.toList());

//             return ResponseEntity.ok(results);
//         } catch (IllegalArgumentException ex) {
//             return ResponseEntity.badRequest().body(ex.getMessage());
//         } catch (Exception e) {
//             return ResponseEntity.status(500).body("Image upload failed");
//         }
//     }

//     // (향후) JSON + 파일 동시 업로드가 필요할 때:
//     // @PostMapping(path="/entries/with-images", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
//     // public ResponseEntity<?> createJourneyWithImages(
//     //     @RequestPart("dto") JourneyRequestDto dto,
//     //     @RequestPart(value = "images", required = false) List<MultipartFile> images,
//     //     HttpServletRequest request
//     // ) { ... }
// }
