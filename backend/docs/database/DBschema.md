-- heat_trip_db 데이터베이스 생성 및 사용
CREATE DATABASE IF NOT EXISTS `heat_trip_db` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE `heat_trip_db`;

-- 1. 사용자 정보 테이블
CREATE TABLE `users` (
  `user_id` INT AUTO_INCREMENT PRIMARY KEY,            -- 고유 사용자 ID (기본 키)
  `name` VARCHAR(50),                                  -- 실명
  `nickname` VARCHAR(50),                              -- 닉네임
  `gender` ENUM('MALE', 'FEMALE', 'OTHER'),            -- 성별
  `age` INT,                                            -- 나이
  `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP,     -- 생성 시각
  `updated_at` DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, -- 수정 시각
  `username` VARCHAR(50) UNIQUE,                       -- 로그인용 ID
  `password` VARCHAR(255),                             -- 암호화된 비밀번호
  `traveler_type` VARCHAR(50),                         -- 여행자 유형 (텍스트)
  `image_url` VARCHAR(255)                             -- 프로필 이미지 URL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2. 여행 스케줄 테이블
CREATE TABLE `travel_schedules` (
  `schedule_id` INT AUTO_INCREMENT PRIMARY KEY,         -- 여행 일정 고유 ID
  `user_id` INT,                                        -- 작성자 ID (users 테이블 참조)
  `title` VARCHAR(100),                                 -- 제목
  `date_from` DATE,                                     -- 시작일
  `date_to` DATE,                                       -- 종료일
  `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP,      -- 생성 시각
  `updated_at` DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, -- 수정 시각
  FOREIGN KEY (`user_id`) REFERENCES `users`(`user_id`) ON DELETE CASCADE
  -- FOREIGN KEY: users 테이블의 user_id와 연결됨
  -- ON DELETE CASCADE: 사용자가 삭제되면 해당 사용자의 일정도 자동으로 삭제됨
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 3. 댓글 테이블
CREATE TABLE `comments` (
  `comment_id` INT AUTO_INCREMENT PRIMARY KEY,          -- 댓글 ID
  `parent_id` INT,                                      -- 부모 댓글 ID (대댓글용, 자기 참조)
  `user_id` INT,                                        -- 작성자 ID (users 테이블 참조)
  `content` TEXT,                                       -- 댓글 내용
  `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP,      -- 작성 시각
  FOREIGN KEY (`user_id`) REFERENCES `users`(`user_id`) ON DELETE CASCADE
  -- 작성자가 삭제되면 댓글도 같이 삭제됨
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 4. 좋아요 로그 테이블
CREATE TABLE `likes` (
  `like_id` INT AUTO_INCREMENT PRIMARY KEY,             -- 좋아요 고유 ID
  `user_id` INT,                                        -- 누른 사용자 ID (users 테이블 참조)
  `post_id` INT,                                        -- 대상 게시글 ID (travel_schedules 참조)
  `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP,      -- 생성 시각
  FOREIGN KEY (`user_id`) REFERENCES `users`(`user_id`) ON DELETE CASCADE,
  FOREIGN KEY (`post_id`) REFERENCES `travel_schedules`(`schedule_id`) ON DELETE CASCADE
  -- 사용자가 삭제되면 해당 사용자의 좋아요도 삭제됨
  -- 게시글이 삭제되면 해당 글의 좋아요도 삭제됨
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 5. 관광지 테이블
CREATE TABLE `attractions` (
  `attraction_id` INT AUTO_INCREMENT PRIMARY KEY,       -- 관광지 ID
  `name` VARCHAR(100),                                  -- 관광지 이름
  `address` VARCHAR(255),                               -- 주소
  `description` TEXT                                    -- 설명
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 6. 해시태그 테이블
CREATE TABLE `hashtags` (
  `hashtag_id` INT AUTO_INCREMENT PRIMARY KEY,          -- 해시태그 ID
  `name` VARCHAR(100) UNIQUE                            -- 해시태그 이름 (예: #산책, #힐링 등)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 7. 해시태그 로그 테이블 (해시태그와 게시글 연결 테이블)
CREATE TABLE `hashtag_logs` (
  `log_id` INT AUTO_INCREMENT PRIMARY KEY,              -- 로그 ID
  `schedule_id` INT,                                    -- 게시글 ID (travel_schedules.schedule_id 참조)
  `hashtag_id` INT,                                     -- 해시태그 ID (hashtags.hashtag_id 참조)
  `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP,      -- 태그 등록 시각
  FOREIGN KEY (`schedule_id`) REFERENCES `travel_schedules`(`schedule_id`) ON DELETE CASCADE,
  FOREIGN KEY (`hashtag_id`) REFERENCES `hashtags`(`hashtag_id`) ON DELETE CASCADE
  -- 게시글이나 해시태그가 삭제되면 자동으로 해당 연결도 삭제됨
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 8. 감정 테이블 (예: joy, sadness, excitement, calm, boredom)
CREATE TABLE `emotions` (
  `emotion_id` INT AUTO_INCREMENT PRIMARY KEY,          -- 감정 ID
  `name` VARCHAR(50) UNIQUE                             -- 감정 이름
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 9. 여행자 유형 테이블 (예: solo, family, couple, friends)
CREATE TABLE `traveler_types` (
  `type_id` INT AUTO_INCREMENT PRIMARY KEY,             -- 유형 ID
  `name` VARCHAR(50) UNIQUE                             -- 유형 이름
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;



[DB 업데이트 쿼리]


