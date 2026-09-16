-- ========================================================================
-- 01_schema.sql — 운영 스키마 정본 (이슈 #58)
--
-- **손으로 고치지 않는다.** 지금 JPA 엔티티가 만드는 스키마를 그대로 뽑은 것이다.
--
--   cd backend
--   ./gradlew test --tests '*SchemaDdlDriftTest*'
--   cp build/generated-schema.sql mysql/init/01_schema.sql
--
-- SchemaDdlDriftTest 가 이 파일과 엔티티가 어긋나면 CI 를 빨간불로 만든다.
--
-- ------------------------------------------------------------------------
-- 왜 이 파일이 생겼나
--
-- 예전에는 mysql/init/ 이 비어 있었다. 저장소 전체에 CREATE TABLE 이 하나도
-- 없었고 prod 는 ddl-auto=validate 라 아무것도 만들지 않는다. 즉 **빈 운영 DB 에
-- 이 앱을 올릴 방법이 저장소에 없었다** — 새 환경 구축도 재해 복구도 경로가
-- 없고, post-start/*.sql 은 전부 ALTER TABLE 이라 테이블이 있다고 전제한다.
--
-- ------------------------------------------------------------------------
-- 실행 순서
--
--   1. 이 파일 (mysql/init) — 컨테이너가 새 볼륨으로 처음 뜰 때 자동 실행
--   2. mysql/post-start/01~05 — 사람이 번호 순으로 (mysql/README.md)
--
-- 이미 돌고 있는 DB 에는 실행하지 마라. '처음 세울 때' 파일이다.
--
-- ------------------------------------------------------------------------
-- FOREIGN_KEY_CHECKS 를 왜 끄는가
--
-- 테이블이 이름순으로 나열돼 있어서, users 를 참조하는 테이블이 users 보다
-- 먼저 나온다. 그대로 실행하면 "Failed to open the referenced table 'users'"
-- 로 죽는다(실측). 순서를 위상정렬하는 대신 검사를 잠시 끈다 — 스키마 복원의
-- 표준 방식이고, 마지막 줄에서 반드시 되돌린다.
-- ========================================================================

SET FOREIGN_KEY_CHECKS = 0;

CREATE TABLE `care_item` (
  `daily_target` int DEFAULT NULL,
  `sort_order` int NOT NULL,
  `archived_at` datetime(6) DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `dog_id` bigint DEFAULT NULL,
  `group_id` bigint NOT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `system_type` varchar(10) DEFAULT NULL,
  `icon` varchar(20) NOT NULL,
  `name` varchar(20) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_careitem_system` (`group_id`,`system_type`),
  KEY `idx_careitem_group` (`group_id`,`sort_order`),
  KEY `idx_careitem_dog` (`dog_id`),
  CONSTRAINT `fk_careitem_dog` FOREIGN KEY (`dog_id`) REFERENCES `dog` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_careitem_group` FOREIGN KEY (`group_id`) REFERENCES `family_group` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `care_log` (
  `care_item_id` bigint DEFAULT NULL,
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  `dog_id` bigint DEFAULT NULL,
  `done_by` bigint DEFAULT NULL,
  `group_id` bigint DEFAULT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `occurred_at` datetime(6) NOT NULL,
  `type` varchar(10) DEFAULT NULL,
  `memo` varchar(500) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_carelog_group` (`group_id`,`occurred_at`),
  KEY `idx_carelog_doneby` (`done_by`),
  KEY `idx_carelog_dog` (`dog_id`,`occurred_at`),
  KEY `fk_carelog_item` (`care_item_id`),
  CONSTRAINT `fk_carelog_dog` FOREIGN KEY (`dog_id`) REFERENCES `dog` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_carelog_doneby` FOREIGN KEY (`done_by`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_carelog_group` FOREIGN KEY (`group_id`) REFERENCES `family_group` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_carelog_item` FOREIGN KEY (`care_item_id`) REFERENCES `care_item` (`id`) ON DELETE SET NULL,
  CONSTRAINT `ck_carelog_type` CHECK ((`type` in (_utf8mb4'water',_utf8mb4'meal',_utf8mb4'walk',_utf8mb4'med',_utf8mb4'vet',_utf8mb4'poop',_utf8mb4'pee')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `chat_message` (
  `change_seq` bigint DEFAULT NULL,
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  `deleted_at` datetime(6) DEFAULT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `reply_to_id` bigint DEFAULT NULL,
  `room_id` bigint NOT NULL,
  `room_seq` bigint NOT NULL,
  `sender_user_id` bigint NOT NULL,
  `content_type` varchar(16) NOT NULL DEFAULT 'text',
  `client_msg_id` varchar(64) DEFAULT NULL,
  `body` text NOT NULL,
  `sender_name` varchar(255) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_chat_room_seq` (`room_id`,`room_seq`),
  UNIQUE KEY `uq_chat_msg_client` (`room_id`,`sender_user_id`,`client_msg_id`),
  KEY `idx_chat_sender` (`sender_user_id`),
  KEY `idx_chat_reply_to` (`reply_to_id`),
  KEY `idx_chat_change` (`room_id`,`change_seq`),
  CONSTRAINT `fk_chat_reply_to` FOREIGN KEY (`reply_to_id`) REFERENCES `chat_message` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_chat_room` FOREIGN KEY (`room_id`) REFERENCES `chat_room` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `chat_message_reaction` (
  `created_at` datetime(6) NOT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `message_id` bigint NOT NULL,
  `user_id` bigint NOT NULL,
  `kind` varchar(20) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_chat_reaction` (`message_id`,`user_id`,`kind`),
  CONSTRAINT `fk_chat_reaction_message` FOREIGN KEY (`message_id`) REFERENCES `chat_message` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `chat_room` (
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  `id` bigint NOT NULL AUTO_INCREMENT,
  `last_change_seq` bigint NOT NULL DEFAULT '0',
  `last_seq` bigint NOT NULL DEFAULT '0',
  `origin_kind` varchar(20) NOT NULL,
  `tag` varchar(20) NOT NULL,
  `name` varchar(50) NOT NULL,
  `origin_ref` varchar(64) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_chat_room_origin` (`origin_kind`,`origin_ref`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `chat_room_invite` (
  `max_uses` int DEFAULT NULL,
  `used_count` int NOT NULL DEFAULT '0',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  `created_by` bigint NOT NULL,
  `expires_at` datetime(6) DEFAULT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `revoked_at` datetime(6) DEFAULT NULL,
  `room_id` bigint NOT NULL,
  `code` varchar(32) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_chat_invite_code` (`code`),
  KEY `idx_chat_invite_room` (`room_id`,`created_at`),
  CONSTRAINT `fk_chat_invite_room` FOREIGN KEY (`room_id`) REFERENCES `chat_room` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `chat_room_member` (
  `rejoin_blocked` bit(1) NOT NULL DEFAULT b'0',
  `id` bigint NOT NULL AUTO_INCREMENT,
  `joined_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  `last_read_seq` bigint NOT NULL DEFAULT '0',
  `muted_at` datetime(6) DEFAULT NULL,
  `removed_at` datetime(6) DEFAULT NULL,
  `removed_by` bigint DEFAULT NULL,
  `room_id` bigint NOT NULL,
  `user_id` bigint NOT NULL,
  `role` varchar(10) NOT NULL DEFAULT 'MEMBER',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_chat_member` (`room_id`,`user_id`),
  KEY `idx_chat_member_user` (`user_id`),
  CONSTRAINT `fk_chat_member_room` FOREIGN KEY (`room_id`) REFERENCES `chat_room` (`id`) ON DELETE CASCADE,
  CONSTRAINT `chat_room_member_chk_1` CHECK ((`role` in (_utf8mb4'OWNER',_utf8mb4'MEMBER')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `comment` (
  `created_at` datetime(6) NOT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `post_id` bigint NOT NULL,
  `user_id` bigint DEFAULT NULL,
  `handle` varchar(255) DEFAULT NULL,
  `body` text NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_comment_post_created` (`post_id`,`created_at`,`id`),
  KEY `idx_comment_user` (`user_id`),
  CONSTRAINT `fk_comment_post` FOREIGN KEY (`post_id`) REFERENCES `post` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_comment_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `course` (
  `distance_m` int NOT NULL,
  `duration_s` int NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` bigint NOT NULL,
  `walk_id` bigint DEFAULT NULL,
  `visibility` varchar(10) NOT NULL,
  `name` varchar(60) NOT NULL,
  `tags` varchar(60) DEFAULT NULL,
  `note` varchar(200) DEFAULT NULL,
  `path` linestring NOT NULL /*!80003 SRID 4326 */,
  PRIMARY KEY (`id`),
  KEY `idx_course_user` (`user_id`,`created_at`),
  KEY `idx_course_public` (`visibility`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `crew` (
  `capacity` int NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `updated_at` datetime(6) DEFAULT NULL,
  `neighborhood_code` varchar(10) DEFAULT NULL,
  `visibility` varchar(10) NOT NULL,
  `name` varchar(30) NOT NULL,
  `intro` varchar(200) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_crew_public` (`visibility`,`neighborhood_code`),
  CONSTRAINT `ck_crew_capacity` CHECK ((`capacity` between 2 and 100)),
  CONSTRAINT `ck_crew_visibility` CHECK ((`visibility` in (_utf8mb4'invite',_utf8mb4'public')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `crew_favor` (
  `on_date` date NOT NULL,
  `asked_by` bigint DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `crew_id` bigint NOT NULL,
  `dog_id` bigint DEFAULT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `schedule_id` bigint DEFAULT NULL,
  `taken_by` bigint DEFAULT NULL,
  `updated_at` datetime(6) DEFAULT NULL,
  `slot` varchar(10) NOT NULL,
  `status` varchar(10) NOT NULL,
  `note` varchar(200) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_crew_favor_crew` (`crew_id`,`on_date`),
  KEY `fk_crew_favor_asker` (`asked_by`),
  KEY `fk_crew_favor_dog` (`dog_id`),
  KEY `fk_crew_favor_taker` (`taken_by`),
  CONSTRAINT `fk_crew_favor_asker` FOREIGN KEY (`asked_by`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_crew_favor_crew` FOREIGN KEY (`crew_id`) REFERENCES `crew` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_crew_favor_dog` FOREIGN KEY (`dog_id`) REFERENCES `dog` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_crew_favor_taker` FOREIGN KEY (`taken_by`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `ck_crew_favor_slot` CHECK ((`slot` in (_utf8mb4'morning',_utf8mb4'afternoon',_utf8mb4'evening'))),
  CONSTRAINT `ck_crew_favor_status` CHECK ((`status` in (_utf8mb4'open',_utf8mb4'taken')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `device_token` (
  `created_at` datetime(6) NOT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `last_seen_at` datetime(6) NOT NULL,
  `platform` varchar(8) NOT NULL,
  `revoked_at` datetime(6) DEFAULT NULL,
  `user_id` bigint NOT NULL,
  `token` varchar(512) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_device_token_token` (`token`),
  KEY `idx_device_token_user` (`user_id`,`revoked_at`),
  CONSTRAINT `chk_device_token_platform` CHECK ((`platform` in (_utf8mb4'android',_utf8mb4'ios')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `dog` (
  `birth` date DEFAULT NULL,
  `neutered` bit(1) NOT NULL DEFAULT b'0',
  `created_at` datetime(6) NOT NULL,
  `deleted_at` datetime(6) DEFAULT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` bigint NOT NULL,
  `size` varchar(10) NOT NULL DEFAULT 'small',
  `species` varchar(10) NOT NULL DEFAULT 'dog',
  `breed` varchar(50) DEFAULT NULL,
  `name` varchar(50) NOT NULL,
  `avatar` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_dog_user` (`user_id`),
  CONSTRAINT `fk_dog_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_dog_size` CHECK ((`size` in (_utf8mb4'small',_utf8mb4'medium',_utf8mb4'large'))),
  CONSTRAINT `ck_dog_species` CHECK ((`species` in (_utf8mb4'dog',_utf8mb4'cat',_utf8mb4'other')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `family_group` (
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  `id` bigint NOT NULL AUTO_INCREMENT,
  `name` varchar(50) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `kto_call_budget` (
  `day` date NOT NULL,
  `used` int NOT NULL,
  `pool` varchar(16) NOT NULL,
  PRIMARY KEY (`day`,`pool`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `media_objects` (
  `duration_ms` int DEFAULT NULL,
  `height` int DEFAULT NULL,
  `width` int DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `deleted_at` datetime(6) DEFAULT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `size` bigint NOT NULL,
  `updated_at` datetime(6) DEFAULT NULL,
  `status` varchar(10) NOT NULL,
  `media_key` varchar(512) NOT NULL,
  `poster_key` varchar(512) DEFAULT NULL,
  `content_type` varchar(255) DEFAULT NULL,
  `original_name` varchar(255) DEFAULT NULL,
  `owner_id` varchar(255) NOT NULL,
  `ref_id` varchar(255) DEFAULT NULL,
  `ref_type` varchar(255) DEFAULT NULL,
  `category` enum('CHAT_IMAGE','JOURNEY_IMAGE','POST_IMAGE','POST_VIDEO','PROFILE_IMAGE','REVIEW_IMAGE','WALK_IMAGE') NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `UK3pkjswl54cvrded30nci3u45t` (`media_key`),
  KEY `idx_media_owner` (`owner_id`),
  KEY `idx_media_ref` (`ref_type`,`ref_id`),
  KEY `idx_media_orphan` (`ref_type`,`created_at`),
  CONSTRAINT `ck_media_status` CHECK ((`status` in (_utf8mb4'pending',_utf8mb4'ready')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `pet_place_detail` (
  `lat` double DEFAULT NULL,
  `lng` double DEFAULT NULL,
  `common_fetched_at` datetime(6) DEFAULT NULL,
  `not_found_at` datetime(6) DEFAULT NULL,
  `pet_fetched_at` datetime(6) DEFAULT NULL,
  `content_type_id` varchar(16) DEFAULT NULL,
  `content_id` varchar(64) NOT NULL,
  `tel` varchar(64) DEFAULT NULL,
  `image` varchar(512) DEFAULT NULL,
  `acmpy_need_mtr` text,
  `acmpy_psbl_cpam` text,
  `addr` varchar(255) DEFAULT NULL,
  `etc_acmpy_info` text,
  `title` varchar(255) DEFAULT NULL,
  `overview` longtext,
  PRIMARY KEY (`content_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `place_catalog` (
  `fail_streak` int NOT NULL,
  `id` int NOT NULL,
  `item_count` int NOT NULL,
  `total_count` int NOT NULL,
  `failed_at` datetime(6) DEFAULT NULL,
  `fetched_at` datetime(6) NOT NULL,
  `source` varchar(16) NOT NULL,
  `etag` varchar(64) NOT NULL,
  `payload` longtext NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_place_catalog_source` (`source`),
  CONSTRAINT `chk_place_catalog_source` CHECK ((`source` in (_utf8mb4'kto',_utf8mb4'localdata',_utf8mb4'durunubi',_utf8mb4'localtrail',_utf8mb4'playground')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `place_cell` (
  `fail_streak` int NOT NULL,
  `item_count` int NOT NULL,
  `lat_idx` int NOT NULL,
  `lng_idx` int NOT NULL,
  `total_count` int NOT NULL,
  `failed_at` datetime(6) DEFAULT NULL,
  `fetched_at` datetime(6) NOT NULL,
  `payload` longtext NOT NULL,
  PRIMARY KEY (`lat_idx`,`lng_idx`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `post` (
  `course_id` bigint DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `dog_id` bigint DEFAULT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `updated_at` datetime(6) DEFAULT NULL,
  `user_id` bigint DEFAULT NULL,
  `board` varchar(20) NOT NULL,
  `content_id` varchar(64) DEFAULT NULL,
  `loc` varchar(100) DEFAULT NULL,
  `title` varchar(200) NOT NULL,
  `handle` varchar(255) DEFAULT NULL,
  `body` text NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_post_board_created` (`board`,`created_at`,`id`),
  KEY `idx_post_user` (`user_id`),
  KEY `idx_post_dog` (`dog_id`,`created_at`,`id`),
  CONSTRAINT `fk_post_dog` FOREIGN KEY (`dog_id`) REFERENCES `dog` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_post_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `chk_post_board` CHECK ((`board` in (_utf8mb4'walk_review',_utf8mb4'pet_place',_utf8mb4'health',_utf8mb4'free',_utf8mb4'brag')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `post_bookmark` (
  `created_at` datetime(6) NOT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `post_id` bigint NOT NULL,
  `user_id` bigint NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_post_bookmark` (`post_id`,`user_id`),
  KEY `idx_post_bookmark_user` (`user_id`,`created_at`,`id`),
  CONSTRAINT `fk_post_bookmark_post` FOREIGN KEY (`post_id`) REFERENCES `post` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_post_bookmark_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `push_preference` (
  `enabled` bit(1) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `user_id` bigint NOT NULL,
  PRIMARY KEY (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `reaction` (
  `created_at` datetime(6) NOT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `post_id` bigint NOT NULL,
  `user_id` bigint DEFAULT NULL,
  `type` varchar(20) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_reaction` (`post_id`,`user_id`,`type`),
  KEY `idx_reaction_user` (`user_id`),
  CONSTRAINT `fk_reaction_post` FOREIGN KEY (`post_id`) REFERENCES `post` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_reaction_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `chk_reaction_type` CHECK ((`type` in (_utf8mb4'help',_utf8mb4'cute',_utf8mb4'empathy')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `refresh_token` (
  `created_at` datetime(6) NOT NULL,
  `expires_at` datetime(6) NOT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `revoked_at` datetime(6) DEFAULT NULL,
  `user_id` bigint NOT NULL,
  `token_hash` varchar(64) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_refresh_token_token_hash` (`token_hash`),
  KEY `idx_refresh_token_user_id` (`user_id`),
  KEY `idx_refresh_token_expires_at` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `report` (
  `created_at` datetime(6) NOT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `reported_user_id` bigint DEFAULT NULL,
  `reporter_user_id` bigint NOT NULL,
  `reason` varchar(16) NOT NULL,
  `memo` varchar(500) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_report_reported` (`reported_user_id`),
  KEY `idx_report_reporter` (`reporter_user_id`),
  CONSTRAINT `chk_report_reason` CHECK ((`reason` in (_utf8mb4'spam',_utf8mb4'abuse',_utf8mb4'sexual',_utf8mb4'fraud',_utf8mb4'other')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `report_snapshot` (
  `author_user_id` bigint DEFAULT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `occurred_at` datetime(6) NOT NULL,
  `report_id` bigint NOT NULL,
  `role` varchar(8) NOT NULL,
  `target_id` bigint NOT NULL,
  `target_ordinal` bigint DEFAULT NULL,
  `content_type` varchar(16) DEFAULT NULL,
  `target_type` varchar(24) NOT NULL,
  `title` varchar(200) DEFAULT NULL,
  `author_name` varchar(255) DEFAULT NULL,
  `body` text,
  PRIMARY KEY (`id`),
  KEY `idx_report_snapshot_report` (`report_id`),
  KEY `idx_report_snapshot_target` (`target_type`,`target_id`),
  CONSTRAINT `fk_report_snapshot_report` FOREIGN KEY (`report_id`) REFERENCES `report` (`id`) ON DELETE CASCADE,
  CONSTRAINT `chk_report_snapshot_role` CHECK ((`role` in (_utf8mb4'target',_utf8mb4'context'))),
  CONSTRAINT `chk_report_snapshot_target_has_body` CHECK (((`role` <> _utf8mb4'target') or (`body` is not null))),
  CONSTRAINT `chk_report_snapshot_target_type` CHECK ((`target_type` in (_utf8mb4'community_post',_utf8mb4'community_comment',_utf8mb4'chat_message',_utf8mb4'chat_room')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `schedule` (
  `at_time` time(6) DEFAULT NULL,
  `on_date` date NOT NULL,
  `repeat_until` date DEFAULT NULL,
  `version` int NOT NULL,
  `assignee` bigint DEFAULT NULL,
  `care_log_id` bigint DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `created_by` bigint NOT NULL,
  `dog_id` bigint DEFAULT NULL,
  `done_at` datetime(6) DEFAULT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `origin_id` bigint DEFAULT NULL,
  `owner_ref` bigint NOT NULL,
  `updated_at` datetime(6) DEFAULT NULL,
  `updated_by` bigint DEFAULT NULL,
  `kind` varchar(10) NOT NULL,
  `owner_kind` varchar(10) NOT NULL,
  `repeat_kind` varchar(10) NOT NULL,
  `status` varchar(10) NOT NULL,
  `title` varchar(100) NOT NULL,
  `memo` varchar(500) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_schedule_owner_date` (`owner_kind`,`owner_ref`,`on_date`),
  KEY `idx_schedule_dog_date` (`dog_id`,`on_date`),
  KEY `fk_schedule_assignee` (`assignee`),
  KEY `fk_schedule_created_by` (`created_by`),
  KEY `fk_schedule_origin` (`origin_id`),
  KEY `fk_schedule_updated_by` (`updated_by`),
  CONSTRAINT `fk_schedule_assignee` FOREIGN KEY (`assignee`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_schedule_created_by` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_schedule_dog` FOREIGN KEY (`dog_id`) REFERENCES `dog` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_schedule_origin` FOREIGN KEY (`origin_id`) REFERENCES `schedule` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_schedule_updated_by` FOREIGN KEY (`updated_by`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `ck_schedule_kind` CHECK ((`kind` in (_utf8mb4'walk',_utf8mb4'vet',_utf8mb4'med',_utf8mb4'groom',_utf8mb4'bath',_utf8mb4'food',_utf8mb4'etc'))),
  CONSTRAINT `ck_schedule_owner_kind` CHECK ((`owner_kind` in (_utf8mb4'dog',_utf8mb4'group',_utf8mb4'room'))),
  CONSTRAINT `ck_schedule_repeat` CHECK ((`repeat_kind` in (_utf8mb4'none',_utf8mb4'daily',_utf8mb4'weekly',_utf8mb4'monthly'))),
  CONSTRAINT `ck_schedule_status` CHECK ((`status` in (_utf8mb4'planned',_utf8mb4'done',_utf8mb4'skipped')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `schedule_exception` (
  `on_date` date NOT NULL,
  `schedule_id` bigint NOT NULL,
  `kind` varchar(10) NOT NULL,
  PRIMARY KEY (`on_date`,`schedule_id`),
  KEY `fk_schedexc_schedule` (`schedule_id`),
  CONSTRAINT `fk_schedexc_schedule` FOREIGN KEY (`schedule_id`) REFERENCES `schedule` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_schedule_exception_kind` CHECK ((`kind` in (_utf8mb4'skip',_utf8mb4'override')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `trail_route` (
  `length_m` int NOT NULL,
  `point_count` int NOT NULL,
  `start_lat` double NOT NULL,
  `start_lng` double NOT NULL,
  `fetched_at` datetime(6) NOT NULL,
  `course_id` varchar(32) NOT NULL,
  `name` varchar(150) NOT NULL,
  `payload` longtext NOT NULL,
  PRIMARY KEY (`course_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `user_block` (
  `blocked_user_id` bigint NOT NULL,
  `blocker_user_id` bigint NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_user_block` (`blocker_user_id`,`blocked_user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `user_consent` (
  `agreed` bit(1) NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` bigint NOT NULL,
  `kind` varchar(16) NOT NULL,
  `version` varchar(16) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_user_consent_user` (`user_id`,`id`),
  CONSTRAINT `chk_user_consent_kind` CHECK ((`kind` in (_utf8mb4'TERMS',_utf8mb4'PRIVACY',_utf8mb4'LOCATION',_utf8mb4'MARKETING')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `users` (
  `age` int DEFAULT NULL,
  `created_at` datetime(6) DEFAULT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `updated_at` datetime(6) DEFAULT NULL,
  `neighborhood_code` varchar(10) DEFAULT NULL,
  `provider` varchar(20) DEFAULT NULL,
  `role` varchar(20) NOT NULL,
  `social_id` varchar(191) DEFAULT NULL,
  `email` varchar(255) DEFAULT NULL,
  `image_url` varchar(255) DEFAULT NULL,
  `name` varchar(255) DEFAULT NULL,
  `nickname` varchar(255) DEFAULT NULL,
  `password` varchar(255) DEFAULT NULL,
  `travel_type` varchar(255) DEFAULT NULL,
  `username` varchar(255) DEFAULT NULL,
  `age_group` enum('OVER14','UNDER14') DEFAULT NULL,
  `gender` enum('FEMALE','MALE','OTHER') DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_users_provider_social_id` (`provider`,`social_id`),
  UNIQUE KEY `UK6dotkott2kjsp8vw4d0m25fb7` (`email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `walk` (
  `distance_m` int NOT NULL,
  `duration_s` int NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `dog_id` bigint NOT NULL,
  `ended_at` datetime(6) DEFAULT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `started_at` datetime(6) NOT NULL,
  `walked_by` bigint DEFAULT NULL,
  `place_source` varchar(16) DEFAULT NULL,
  `weather` varchar(30) DEFAULT NULL,
  `client_walk_id` varchar(64) NOT NULL,
  `place_content_id` varchar(64) DEFAULT NULL,
  `place_name` varchar(120) DEFAULT NULL,
  `memo` varchar(500) DEFAULT NULL,
  `path_t` json DEFAULT NULL,
  `path` linestring /*!80003 SRID 4326 */ DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_walk_client` (`dog_id`,`client_walk_id`),
  KEY `idx_walk_dog` (`dog_id`,`started_at`),
  KEY `idx_walk_dog_created` (`dog_id`,`created_at`,`id`),
  KEY `idx_walk_place` (`place_source`,`place_content_id`),
  KEY `fk_walk_walkedby` (`walked_by`),
  CONSTRAINT `fk_walk_dog` FOREIGN KEY (`dog_id`) REFERENCES `dog` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_walk_walkedby` FOREIGN KEY (`walked_by`) REFERENCES `users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `walk_dog` (
  `dog_id` bigint NOT NULL,
  `walk_id` bigint NOT NULL,
  PRIMARY KEY (`dog_id`,`walk_id`),
  KEY `fk_walkdog_walk` (`walk_id`),
  CONSTRAINT `fk_walkdog_dog` FOREIGN KEY (`dog_id`) REFERENCES `dog` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_walkdog_walk` FOREIGN KEY (`walk_id`) REFERENCES `walk` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `walk_note` (
  `group_id` bigint NOT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `updated_at` datetime(6) NOT NULL,
  `updated_by` bigint DEFAULT NULL,
  `body` varchar(500) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_walknote_group` (`group_id`),
  KEY `fk_walknote_updatedby` (`updated_by`),
  CONSTRAINT `fk_walknote_group` FOREIGN KEY (`group_id`) REFERENCES `family_group` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_walknote_updatedby` FOREIGN KEY (`updated_by`) REFERENCES `users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `weekly_insight` (
  `calls` int NOT NULL,
  `week_start` date NOT NULL,
  `dog_id` bigint NOT NULL,
  `feedback` varchar(8) DEFAULT NULL,
  `feedback_at` datetime(6) DEFAULT NULL,
  `generated_at` datetime(6) NOT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` bigint NOT NULL,
  `input_hash` varchar(64) NOT NULL,
  `model` varchar(64) NOT NULL,
  `text` text,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_weekly_insight` (`user_id`,`dog_id`,`week_start`),
  KEY `idx_weekly_insight_generated` (`generated_at`),
  CONSTRAINT `fk_weekly_insight_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_weekly_insight_feedback` CHECK ((`feedback` in (_utf8mb4'up',_utf8mb4'down')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

SET FOREIGN_KEY_CHECKS = 1;
