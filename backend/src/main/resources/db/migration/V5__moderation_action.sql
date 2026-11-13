-- ========================================================================
-- V5__moderation_action.sql — 운영자 조치 기록 (이슈 #718)
--
-- 신고를 처리한 결과를 한 줄씩 덧붙이는 표다. 이번에 쓰는 것은 둘이다.
--
--   remove  — 신고된 글·댓글을 지웠다. 지우기 직전의 사본(작성자·제목·본문·쓴 시각)을
--             함께 남긴다. 글은 작성자가 지울 때와 같은 길로 지워져 댓글·반응·북마크·사진이
--             함께 사라지므로, 무엇을 지웠는지 아는 곳은 이 줄뿐이다. 신고 사본(report_snapshot)
--             은 신고한 때의 글이라 그 뒤에 고쳐진 글을 지웠다면 내용이 다르다.
--   dismiss — 살펴봤고 지울 것이 없다.
--
-- suspend · lift(사람 정지·해제)는 다음 조각이 같은 표에 쓴다. kind 의 CHECK 이 넷을 미리
-- 받아 두는 것은 그때 이 표를 다시 고치지 않으려는 것이다.
--
-- 왜 report 의 상태 칸이 아닌가
--
--   한 신고에 조치가 여럿일 수 있고(글 삭제와 작성자 정지), 정지·해제는 신고 없이도
--   일어난다. 그래서 무엇을·언제·누가·왜 를 줄마다 남기는 이력 표로 둔다.
--
-- users 로 FK 를 안 건다
--
--   subject_user_id 는 값으로만 가리킨다 — report · user_block 과 같은 규약이다. 탈퇴가
--   조치 기록을 지우면 안 된다. report 로는 FK 를 건다 — 신고는 지워지지 않는다.
--
-- 엔티티와 같아야 한다
--
--   moderation.entity.ModerationAction 이 같은 표를 말한다. 통합 테스트는 엔티티에서 표를
--   만들므로, 이 파일의 CHECK·FK·인덱스가 엔티티와 어긋나면 운영만 다르게 돈다.
--   CanonicalSchemaMatchesMigrationsTest 가 그 둘을 대조한다.
--
-- 옛 코드와도 맞는다
--
--   표를 더하기만 한다. 이 파일이 먼저 돌고 옛 코드가 떠 있어도 아무도 이 표를 안 읽는다.
--   옛 코드를 다시 띄워도 Flyway 는 자기가 모르는 V5 를 건너뛴다(FlywayBuildsTheSchemaTest).
--
-- 되돌리기
--
--   DROP TABLE moderation_action;
--   DELETE FROM flyway_schema_history WHERE version = '5';
--   — 조치 기록과 지운 글의 사본이 함께 사라진다. 지운 글 자체는 이미 없으므로 먼저 이 표를
--     덤프해 둔다. 옛 코드로 돌아가는 것만이라면 표를 지울 필요가 없다(위 문단).
-- ========================================================================

CREATE TABLE `moderation_action` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  -- remove · dismiss · suspend · lift
  `kind` varchar(8) NOT NULL,
  -- 어느 신고에 대한 조치인가. 신고 없이 한 정지·해제면 비어 있다.
  `report_id` bigint DEFAULT NULL,
  -- 조치를 받은 사람 — 지운 글의 작성자, 정지된 사람. 탈퇴한 작성자면 비어 있다.
  `subject_user_id` bigint DEFAULT NULL,
  -- 지운 대상 — 신고 사본과 같은 낱말(community_post · community_comment · chat_message).
  `target_type` varchar(24) DEFAULT NULL,
  `target_id` bigint DEFAULT NULL,
  -- 정지가 끝나는 시각(UTC). suspend 에만 있고, 비면 무기한이다.
  `ends_at` datetime(6) DEFAULT NULL,
  -- 지우기 직전의 사본.
  `author_name` varchar(255) DEFAULT NULL,
  `title` varchar(200) DEFAULT NULL,
  `body` text,
  `occurred_at` datetime(6) DEFAULT NULL,
  -- 왜 · 누가(서버에 들어간 계정 이름 — 운영 스크립트가 채운다) · 언제(UTC).
  `reason` varchar(500) NOT NULL,
  `actor` varchar(64) NOT NULL,
  `created_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  -- 정지 판정의 뜨거운 길 — 이 사람의 마지막 정지·해제 한 줄(다음 조각).
  KEY `idx_moderation_action_subject` (`subject_user_id`,`id`),
  KEY `idx_moderation_action_report` (`report_id`),
  CONSTRAINT `fk_moderation_action_report` FOREIGN KEY (`report_id`) REFERENCES `report` (`id`),
  CONSTRAINT `chk_moderation_action_kind`
    CHECK (`kind` in ('remove','suspend','lift','dismiss')),
  CONSTRAINT `chk_moderation_action_target_type`
    CHECK (`target_type` is null or `target_type` in ('community_post','community_comment','chat_message')),
  -- 지웠다면 무엇을 지웠는지가 있어야 한다 — 이 표가 있는 이유다.
  CONSTRAINT `chk_moderation_action_remove_has_copy`
    CHECK (`kind` <> 'remove' or (`target_type` is not null and `target_id` is not null and `body` is not null)),
  CONSTRAINT `chk_moderation_action_standing_has_subject`
    CHECK (`kind` not in ('suspend','lift') or `subject_user_id` is not null),
  CONSTRAINT `chk_moderation_action_ends_only_on_suspend`
    CHECK (`kind` = 'suspend' or `ends_at` is null)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
