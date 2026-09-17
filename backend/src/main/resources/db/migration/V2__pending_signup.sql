-- ========================================================================
-- V2__pending_signup.sql — 이메일 가입 대기 (이슈 #635)
--
-- **인증 전에는 사용자를 안 만든다.** 가입 요청은 여기 한 행으로 남고, 코드가 맞을 때
-- 비로소 `users` 에 들어간다.
--
-- 왜 `users` 에 email_verified 컬럼을 두지 않았나
--
--   1. 미인증 행이 `users.email` 의 UNIQUE 를 잡는다. 남이 내 이메일로 가입을 **시도만**
--      해 놓아도 내가 그 주소로 가입을 못 하게 된다
--   2. 로그인·프로필·탈퇴 등 `users` 를 읽는 모든 자리가 "인증됐나" 를 함께 봐야 한다.
--      한 곳이라도 빠뜨리면 미인증 계정이 조용히 들어온다
--
-- 대기 행은 만료되면 쓰레기다. 지우는 것은 `PendingSignupPurgeScheduler` 가 한다.
-- ========================================================================

CREATE TABLE `pending_signup` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  -- 이메일 하나에 대기 행 하나. 다시 요청하면 옛 행을 덮어쓴다 — 코드를 여러 개 살려 두면
  -- "몇 번째 메일의 코드인지" 를 사용자도 우리도 모른다.
  `email` varchar(255) NOT NULL,
  -- 이미 해시된 비밀번호다. 평문은 어디에도 안 남는다.
  `password_hash` varchar(255) NOT NULL,
  `nickname` varchar(100) NOT NULL,
  -- 코드도 해시로 둔다. 이 표를 읽을 수 있는 사람이 남의 메일함 없이 가입을 마칠 수 있으면
  -- 인증이 아니다.
  `code_hash` varchar(255) NOT NULL,
  `expires_at` datetime(6) NOT NULL,
  -- 틀린 시도 횟수. 넘으면 그 행을 죽인다 — 6자리는 무차별로 100만분의 1이다.
  `attempts` int NOT NULL DEFAULT 0,
  `created_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_pending_signup_email` (`email`),
  -- 만료된 행을 쓸어 담을 때 쓴다.
  KEY `idx_pending_signup_expires` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
