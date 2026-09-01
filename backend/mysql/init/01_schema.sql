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

CREATE TABLE `bookmarks` (
  `created_at` datetime(6) DEFAULT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` bigint NOT NULL,
  `content_id` varchar(64) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `UKk1k57s35xli8cwue7u9l4dnhx` (`user_id`,`content_id`),
  CONSTRAINT `FKdbsho2e05w5r13fkjqfjmge5f` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `card_comment` (
  `card_id` bigint NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` bigint NOT NULL,
  `body` varchar(280) NOT NULL,
  `handle` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `card_reaction` (
  `card_id` bigint NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` bigint NOT NULL,
  `reaction_type` varchar(255) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_card_reaction_card_user_type` (`card_id`,`user_id`,`reaction_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `care_log` (
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  `dog_id` bigint DEFAULT NULL,
  `done_by` bigint DEFAULT NULL,
  `group_id` bigint DEFAULT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `occurred_at` datetime(6) NOT NULL,
  `type` varchar(10) NOT NULL,
  `memo` varchar(500) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_carelog_group` (`group_id`,`occurred_at`),
  KEY `idx_carelog_doneby` (`done_by`),
  CONSTRAINT `fk_carelog_doneby` FOREIGN KEY (`done_by`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_carelog_group` FOREIGN KEY (`group_id`) REFERENCES `family_group` (`id`) ON DELETE SET NULL,
  CONSTRAINT `ck_carelog_type` CHECK ((`type` in (_utf8mb4'water',_utf8mb4'meal',_utf8mb4'walk',_utf8mb4'med',_utf8mb4'vet')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `cat3_category_mapping` (
  `category_id` int DEFAULT NULL,
  `mapping_id` bigint NOT NULL AUTO_INCREMENT,
  `cat3_code` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`mapping_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `chat_block` (
  `blocked_user_id` bigint NOT NULL,
  `blocker_user_id` bigint NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_chat_block` (`blocker_user_id`,`blocked_user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `chat_message` (
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  `deleted_at` datetime(6) DEFAULT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
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
  CONSTRAINT `fk_chat_room` FOREIGN KEY (`room_id`) REFERENCES `chat_room` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `chat_report` (
  `context_from_seq` bigint NOT NULL,
  `context_to_seq` bigint NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `reported_user_id` bigint NOT NULL,
  `reporter_user_id` bigint NOT NULL,
  `room_id` bigint NOT NULL,
  `reason` varchar(16) NOT NULL,
  `memo` varchar(500) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_chat_report_reported` (`reported_user_id`),
  KEY `idx_chat_report_reporter` (`reporter_user_id`),
  KEY `idx_chat_report_room` (`room_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `chat_reported_message` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `message_id` bigint DEFAULT NULL,
  `report_id` bigint NOT NULL,
  `room_seq` bigint NOT NULL,
  `sender_user_id` bigint NOT NULL,
  `sent_at` datetime(6) NOT NULL,
  `content_type` varchar(16) NOT NULL,
  `body` text NOT NULL,
  `sender_name` varchar(255) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_chat_reported_msg` (`report_id`,`room_seq`),
  CONSTRAINT `fk_chat_reported_msg_report` FOREIGN KEY (`report_id`) REFERENCES `chat_report` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `chat_room` (
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  `id` bigint NOT NULL AUTO_INCREMENT,
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

CREATE TABLE `collection_items` (
  `collection_id` bigint NOT NULL,
  `created_at` datetime(6) DEFAULT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` bigint NOT NULL,
  `content_id` varchar(64) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `UK9io6dptmsfqnrumptrwye63lm` (`user_id`,`collection_id`,`content_id`),
  KEY `FKrkp5wpkksx5aqex6v4qnq9912` (`collection_id`),
  CONSTRAINT `FKqbqdudvmw7hwi6ijdfg2vtrq4` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `FKrkp5wpkksx5aqex6v4qnq9912` FOREIGN KEY (`collection_id`) REFERENCES `collections` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `collections` (
  `created_at` datetime(6) DEFAULT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `updated_at` datetime(6) DEFAULT NULL,
  `user_id` bigint NOT NULL,
  `name` varchar(60) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `UK9jlux1cwd4hfslei7lc96f29d` (`user_id`,`name`),
  CONSTRAINT `FKn7pdedyqaiddr0uxdj603my7d` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `dog` (
  `birth` date DEFAULT NULL,
  `neutered` bit(1) NOT NULL DEFAULT b'0',
  `created_at` datetime(6) NOT NULL,
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

CREATE TABLE `emotion_card` (
  `created_at` datetime(6) NOT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `place_id` bigint DEFAULT NULL,
  `user_id` bigint NOT NULL,
  `body` varchar(280) DEFAULT NULL,
  `handle` varchar(255) DEFAULT NULL,
  `mood_key` varchar(255) NOT NULL,
  `place_name` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `emotion_categories` (
  `category_id` int NOT NULL,
  `category_emoji` varchar(255) DEFAULT NULL,
  `category_name` varchar(255) DEFAULT NULL,
  `characteristic` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`category_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `emotion_feedbacks` (
  `client_timestamp` datetime(6) DEFAULT NULL,
  `content_id` bigint NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `after_emotion` varchar(32) NOT NULL,
  `before_emotion` varchar(32) NOT NULL,
  `content` longtext,
  `feature_ratings_json` tinytext,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `emotion_reviews` (
  `delta_arousal` double NOT NULL,
  `delta_dominance` double NOT NULL,
  `delta_valence` double NOT NULL,
  `helpful_count` int NOT NULL,
  `content_id` bigint NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `review_date` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `after_emotion` varchar(32) NOT NULL,
  `before_emotion` varchar(32) NOT NULL,
  `author` varchar(100) NOT NULL,
  `content` longtext,
  `images_json` tinytext,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `family_group` (
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  `id` bigint NOT NULL AUTO_INCREMENT,
  `name` varchar(50) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `feedback` (
  `created_at` datetime(6) DEFAULT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `updated_at` datetime(6) DEFAULT NULL,
  `user_id` bigint DEFAULT NULL,
  `app_version` varchar(50) DEFAULT NULL,
  `category` varchar(50) DEFAULT NULL,
  `device_info` varchar(120) DEFAULT NULL,
  `content` longtext,
  `status` enum('IN_PROGRESS','NEW','RESOLVED') DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `FKpwwmhguqianghvi1wohmtsm8l` (`user_id`),
  CONSTRAINT `FKpwwmhguqianghvi1wohmtsm8l` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `journey` (
  `date` date DEFAULT NULL,
  `id` int NOT NULL AUTO_INCREMENT,
  `schedule_id` int DEFAULT NULL,
  `created_at` datetime(6) DEFAULT NULL,
  `place_id` bigint DEFAULT NULL,
  `updated_at` datetime(6) DEFAULT NULL,
  `user_id` bigint NOT NULL,
  `body` varchar(255) DEFAULT NULL,
  `location` varchar(255) DEFAULT NULL,
  `mood_label` varchar(255) DEFAULT NULL,
  `title` varchar(255) DEFAULT NULL,
  `weather_label` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `FKk0vc19jo5wygypce9f3okcvvs` (`schedule_id`),
  KEY `FK9xglfr1fkvuoypqh75fgxju5o` (`user_id`),
  CONSTRAINT `FK9xglfr1fkvuoypqh75fgxju5o` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `FKk0vc19jo5wygypce9f3okcvvs` FOREIGN KEY (`schedule_id`) REFERENCES `schedule` (`schedule_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `journey_photos` (
  `journey_id` int NOT NULL,
  `photo_url` varchar(255) DEFAULT NULL,
  KEY `FKqanwlnup01qpasii1iggj7s9x` (`journey_id`),
  CONSTRAINT `FKqanwlnup01qpasii1iggj7s9x` FOREIGN KEY (`journey_id`) REFERENCES `journey` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `kto_call_budget` (
  `day` date NOT NULL,
  `used` int NOT NULL,
  `pool` varchar(16) NOT NULL,
  PRIMARY KEY (`day`,`pool`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `media_objects` (
  `created_at` datetime(6) NOT NULL,
  `deleted_at` datetime(6) DEFAULT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `size` bigint NOT NULL,
  `updated_at` datetime(6) DEFAULT NULL,
  `media_key` varchar(512) NOT NULL,
  `content_type` varchar(255) DEFAULT NULL,
  `original_name` varchar(255) DEFAULT NULL,
  `owner_id` varchar(255) NOT NULL,
  `ref_id` varchar(255) DEFAULT NULL,
  `ref_type` varchar(255) DEFAULT NULL,
  `category` enum('JOURNEY_IMAGE','PROFILE_IMAGE','REVIEW_IMAGE') NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `UK3pkjswl54cvrded30nci3u45t` (`media_key`),
  KEY `idx_media_owner` (`owner_id`),
  KEY `idx_media_ref` (`ref_type`,`ref_id`)
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

CREATE TABLE `place_descriptions` (
  `place_id` varchar(16) NOT NULL,
  `short_desc_1` tinytext,
  `short_desc_2` tinytext,
  PRIMARY KEY (`place_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `place_features` (
  `adventure` double DEFAULT NULL,
  `conf_adventure` double DEFAULT NULL,
  `conf_culture` double DEFAULT NULL,
  `conf_nature_healing` double DEFAULT NULL,
  `conf_quiet` double DEFAULT NULL,
  `conf_sociality` double DEFAULT NULL,
  `conf_spirituality` double DEFAULT NULL,
  `culture` double DEFAULT NULL,
  `n_blogs` int DEFAULT NULL,
  `n_reviews` int DEFAULT NULL,
  `nature_healing` double DEFAULT NULL,
  `quiet` double DEFAULT NULL,
  `sociality` double DEFAULT NULL,
  `spirituality` double DEFAULT NULL,
  `link_id` bigint NOT NULL,
  `updated_at` datetime(6) DEFAULT NULL,
  `method_ver` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`link_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `place_hashtags` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `place_id` varchar(16) NOT NULL,
  `hashtag` varchar(100) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_ph_place` (`place_id`),
  KEY `idx_ph_hashtag` (`hashtag`)
) ENGINE=InnoDB AUTO_INCREMENT=286 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `place_kakao_links` (
  `kakao_mapx` double DEFAULT NULL,
  `kakao_mapy` double DEFAULT NULL,
  `created` datetime(6) NOT NULL,
  `id` bigint NOT NULL,
  `place_url` varchar(512) DEFAULT NULL,
  `title` varchar(255) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_place_kakao_created` (`created`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `place_simple_tags` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `place_id` varchar(16) NOT NULL,
  `tag` varchar(100) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_pst_place` (`place_id`),
  KEY `idx_pst_tag` (`tag`)
) ENGINE=InnoDB AUTO_INCREMENT=286 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `place_star_ratings` (
  `rating` double DEFAULT NULL,
  `link_id` bigint NOT NULL,
  `updated_at` datetime(6) DEFAULT NULL,
  `source` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`link_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `place_trait_snapshots` (
  `a_score` double DEFAULT NULL,
  `crowdness` double DEFAULT NULL,
  `d_score` double DEFAULT NULL,
  `noise` double DEFAULT NULL,
  `p_score` double DEFAULT NULL,
  `sociality` double DEFAULT NULL,
  `snapshot_at` datetime(6) DEFAULT NULL,
  `cat3` varchar(16) NOT NULL,
  `cat3name` varchar(255) DEFAULT NULL,
  `hashtags` tinytext,
  `short_desc1` tinytext,
  `short_desc2` tinytext,
  `simple_tags` tinytext,
  PRIMARY KEY (`cat3`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `place_traits` (
  `a_score` double DEFAULT NULL,
  `crowdness` double DEFAULT NULL,
  `d_score` double DEFAULT NULL,
  `del_state` int DEFAULT NULL,
  `noise` double DEFAULT NULL,
  `p_score` double DEFAULT NULL,
  `sociality` double DEFAULT NULL,
  `place_id` varchar(16) NOT NULL,
  `name` varchar(200) NOT NULL,
  `hash1` varchar(255) DEFAULT NULL,
  `hash2` varchar(255) DEFAULT NULL,
  `hash3` varchar(255) DEFAULT NULL,
  `location_type` varchar(255) DEFAULT NULL,
  `short_descript1` varchar(255) DEFAULT NULL,
  `short_descript2` varchar(255) DEFAULT NULL,
  `simple_tag1` varchar(255) DEFAULT NULL,
  `simple_tag2` varchar(255) DEFAULT NULL,
  `simple_tag3` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`place_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `places` (
  `areacode` int DEFAULT NULL,
  `l_dong_regn_cd` int DEFAULT NULL,
  `l_dong_signgu_cd` int DEFAULT NULL,
  `mapx` double DEFAULT NULL,
  `mapy` double DEFAULT NULL,
  `sigungucode` int DEFAULT NULL,
  `ugc_count` int NOT NULL,
  `contentid` bigint NOT NULL,
  `createdtime` datetime(6) DEFAULT NULL,
  `modifiedtime` datetime(6) DEFAULT NULL,
  `zipcode` varchar(20) DEFAULT NULL,
  `tel` varchar(100) DEFAULT NULL,
  `addr1` varchar(255) DEFAULT NULL,
  `addr2` varchar(255) DEFAULT NULL,
  `cat1` varchar(255) DEFAULT NULL,
  `cat2` varchar(255) DEFAULT NULL,
  `cat3` varchar(255) DEFAULT NULL,
  `contenttypeid` varchar(255) DEFAULT NULL,
  `firstimage` varchar(255) DEFAULT NULL,
  `firstimage2` varchar(255) DEFAULT NULL,
  `mlevel` varchar(255) DEFAULT NULL,
  `title` varchar(255) DEFAULT NULL,
  `search_text` longtext,
  `seed_emotion` json DEFAULT NULL,
  `ugc_emotion` json DEFAULT NULL,
  PRIMARY KEY (`contentid`)
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

CREATE TABLE `schedule` (
  `date_from` date DEFAULT NULL,
  `date_to` date DEFAULT NULL,
  `schedule_id` int NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) DEFAULT NULL,
  `updated_at` datetime(6) DEFAULT NULL,
  `user_id` bigint NOT NULL,
  `title` varchar(100) DEFAULT NULL,
  `content` varchar(1000) DEFAULT NULL,
  PRIMARY KEY (`schedule_id`),
  KEY `FKdn5svbxyacce1gpfiawk7iqtc` (`user_id`),
  CONSTRAINT `FKdn5svbxyacce1gpfiawk7iqtc` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `users` (
  `age` int DEFAULT NULL,
  `agree_marketing` bit(1) DEFAULT NULL,
  `agree_privacy` bit(1) DEFAULT NULL,
  `agree_tos` bit(1) DEFAULT NULL,
  `created_at` datetime(6) DEFAULT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `marketing_agreed_at` datetime(6) DEFAULT NULL,
  `privacy_agreed_at` datetime(6) DEFAULT NULL,
  `tos_agreed_at` datetime(6) DEFAULT NULL,
  `updated_at` datetime(6) DEFAULT NULL,
  `provider` varchar(20) DEFAULT NULL,
  `role` varchar(20) NOT NULL,
  `social_id` varchar(191) DEFAULT NULL,
  `email` varchar(255) DEFAULT NULL,
  `image_url` varchar(255) DEFAULT NULL,
  `marketing_version` varchar(255) DEFAULT NULL,
  `name` varchar(255) DEFAULT NULL,
  `nickname` varchar(255) DEFAULT NULL,
  `password` varchar(255) DEFAULT NULL,
  `privacy_version` varchar(255) DEFAULT NULL,
  `tos_version` varchar(255) DEFAULT NULL,
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
  `weather` varchar(30) DEFAULT NULL,
  `client_walk_id` varchar(64) NOT NULL,
  `memo` varchar(500) DEFAULT NULL,
  `path` linestring /*!80003 SRID 4326 */ DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_walk_client` (`dog_id`,`client_walk_id`),
  KEY `idx_walk_dog` (`dog_id`,`started_at`),
  KEY `idx_walk_dog_created` (`dog_id`,`created_at`,`id`),
  CONSTRAINT `fk_walk_dog` FOREIGN KEY (`dog_id`) REFERENCES `dog` (`id`) ON DELETE CASCADE
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

SET FOREIGN_KEY_CHECKS = 1;
