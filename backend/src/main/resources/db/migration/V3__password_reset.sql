-- ========================================================================
-- V3__password_reset.sql — 비밀번호 재설정 (이슈 #635 조각 ③)
--
-- 가입 인증(V2)과 같은 모양이다: 해시된 여섯 자리, 만료 시각, 틀린 횟수.
-- 다른 점은 **이미 있는 계정에만 생긴다** 는 것이라 `user_id` 로 건다.
--
-- 왜 이메일이 아니라 user_id 인가
--
--   1. 이메일은 바뀔 수 있고, 바뀌는 순간 살아 있는 재설정이 주인을 잃는다
--   2. 없는 주소로 요청이 와도 **행을 안 만든다.** 행이 생기면 그 표를 읽을 수 있는
--      사람이 "누가 이 앱을 쓰는가" 를 셀 수 있다
--
-- users 로 FK 를 안 건다 — refresh_token 과 같은 판단이다. 탈퇴 정리 경로를 FK 에
-- 맡기면 그 경로가 표마다 달라진다. 주인 없는 행은 만료되어 사라지고, 그 사이에
-- 코드를 맞혀도 사용자 조회에서 막힌다.
-- ========================================================================

CREATE TABLE `password_reset` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  -- 한 사람에 살아 있는 재설정 하나. 다시 요청하면 옛 행을 덮어쓴다 — 코드를 여러 개
  -- 살려 두면 "몇 번째 메일의 코드인지" 를 사용자도 우리도 모른다.
  `user_id` bigint NOT NULL,
  -- 코드도 해시로 둔다. 이 표를 읽을 수 있는 사람이 남의 메일함 없이 남의 비밀번호를
  -- 바꿀 수 있으면 인증이 아니다.
  `code_hash` varchar(255) NOT NULL,
  `expires_at` datetime(6) NOT NULL,
  -- 틀린 시도 횟수. 넘으면 그 행을 죽인다 — 6자리는 무차별로 100만분의 1이다.
  `attempts` int NOT NULL DEFAULT 0,
  `created_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_password_reset_user` (`user_id`),
  -- 만료된 행을 쓸어 담을 때 쓴다.
  KEY `idx_password_reset_expires` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
