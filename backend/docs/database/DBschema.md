> # ⚠️ 폐기됨 — 이 문서가 설명하는 스키마는 존재하지 않습니다
>
> **실행하지 마십시오. 참조하지 마십시오.**
>
> 아래 DDL 은 이 저장소가 감정여행(heattrip) 앱이던 시절의 것입니다. 반려(Pawloop)로
> 피벗하면서 스키마가 통째로 바뀌었고, 여기 적힌 테이블 대부분은 지금 DB 에 없습니다.
> 남아 있는 이름조차 모양이 다릅니다 — 예를 들어 여기 `users` 는 `user_id INT` ·
> `password` · `traveler_type` 를 가진 자체 회원가입 모델인데, 실제 `users` 는
> `id BIGINT` · `provider` · `social_id` · `age_group enum('OVER14','UNDER14')` 의
> 소셜 계정 모델입니다. 이걸 보고 엔티티를 매핑하면 컴파일도 안 되고, 운 나쁘면
> `CREATE DATABASE` 부터 실행하게 됩니다.
>
> **지금 어디를 봐야 하는가**
>
> | 알고 싶은 것 | 볼 곳 |
> |---|---|
> | 지금 DB 에 실제로 있는 것 | `backend/mysql/init/01_schema.sql` — **정본**. JPA 엔티티가 이 스키마를 만든다 |
> | 계획을 포함한 전체 데이터 모델 | `docs/03-database/schema.md` (§1 `users`·§2 `refresh_token` 만 실재, 나머지는 계획) |
> | 관계 개요 | `docs/03-database/erd.md` |
> | 운영 SQL·런북 | `backend/mysql/README.md` |
>
> **왜 지우지 않았는가.** 이 파일을 참조하는 코드·문서·테스트는 하나도 없습니다
> (저장소 전체 grep 0건). 그러니 지워도 아무것도 깨지지 않습니다. 그런데도 남기는
> 이유는, 아무 표시 없이 사라진 문서는 다음 사람이 git 히스토리에서 다시 파내 오기
> 때문입니다. **"이건 아니다" 라고 적힌 문서가 없는 문서보다 낫습니다.** 이 배너를
> 떼고 싶다면 파일을 통째로 지우십시오 — 배너만 떼는 것이 가장 나쁜 선택입니다.
>
> 같은 디렉터리의 `2026-08-29-users-social-account-model.sql` 은 유효합니다 —
> 그쪽이 지금 모델입니다.

```sql
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
```
