-- ============================================================================
-- 01_schema.sql — 운영 스키마 정본 (이슈 #58)
--
-- 이 파일은 **손으로 고치지 않는다.** JPA 엔티티에서 생성한다.
--
--   cd backend
--   ./gradlew test --tests '*SchemaDdlDriftTest*'
--   cp build/generated-schema.sql mysql/init/01_schema.sql
--
-- SchemaDdlDriftTest 가 이 파일과 엔티티가 어긋나면 CI 를 빨간불로 만든다.
-- 엔티티를 고쳤는데 이 파일을 안 고치면 거기서 걸린다.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- 왜 이 파일이 생겼나
--
-- 예전에는 mysql/init/ 이 비어 있었다. 저장소 전체에 CREATE TABLE 이 하나도
-- 없었고, prod 는 ddl-auto=validate 라 아무것도 만들지 않는다. 즉 **빈 운영 DB 에
-- 이 앱을 올릴 방법이 저장소에 없었다** — 새 환경 구축도 재해 복구도 경로가 없고,
-- post-start/*.sql 은 전부 ALTER TABLE 이라 테이블이 이미 있다고 전제한다.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- 실행 순서
--
--   1. 이 파일 (mysql/init) — 컨테이너가 새 볼륨으로 처음 뜰 때 자동 실행된다
--   2. mysql/post-start/01~05 — 사람이 번호 순으로 실행한다 (mysql/README.md)
--
-- 이미 돌고 있는 DB 에는 실행하지 마라. 이건 '처음 세울 때' 파일이다.
-- ============================================================================

create table bookmarks (created_at datetime(6), id bigint not null auto_increment, user_id bigint not null, content_id varchar(64) not null, primary key (id)) engine=InnoDB;
create table card_comment (card_id bigint not null, created_at datetime(6) not null, id bigint not null auto_increment, user_id bigint not null, body varchar(280) not null, handle varchar(255), primary key (id)) engine=InnoDB;
create table card_reaction (card_id bigint not null, created_at datetime(6) not null, id bigint not null auto_increment, user_id bigint not null, reaction_type varchar(255) not null, primary key (id)) engine=InnoDB;
create table cat3_category_mapping (category_id integer, mapping_id bigint not null auto_increment, cat3_code varchar(255), primary key (mapping_id)) engine=InnoDB;
create table collection_items (collection_id bigint not null, created_at datetime(6), id bigint not null auto_increment, user_id bigint not null, content_id varchar(64) not null, primary key (id)) engine=InnoDB;
create table collections (created_at datetime(6), id bigint not null auto_increment, updated_at datetime(6), user_id bigint not null, name varchar(60) not null, primary key (id)) engine=InnoDB;
create table emotion_card (created_at datetime(6) not null, id bigint not null auto_increment, place_id bigint, user_id bigint not null, body varchar(280), handle varchar(255), mood_key varchar(255) not null, place_name varchar(255), primary key (id)) engine=InnoDB;
create table emotion_categories (category_id integer not null, category_emoji varchar(255), category_name varchar(255), characteristic varchar(255), primary key (category_id)) engine=InnoDB;
create table emotion_feedbacks (client_timestamp datetime(6), content_id bigint not null, created_at datetime(6) not null, id bigint not null auto_increment, after_emotion varchar(32) not null, before_emotion varchar(32) not null, content longtext, feature_ratings_json tinytext, primary key (id)) engine=InnoDB;
create table emotion_reviews (delta_arousal float(53) not null, delta_dominance float(53) not null, delta_valence float(53) not null, helpful_count integer not null, content_id bigint not null, created_at datetime(6) not null, id bigint not null auto_increment, review_date datetime(6) not null, updated_at datetime(6) not null, after_emotion varchar(32) not null, before_emotion varchar(32) not null, author varchar(100) not null, content longtext, images_json tinytext, primary key (id)) engine=InnoDB;
create table feedback (created_at datetime(6), id bigint not null auto_increment, updated_at datetime(6), user_id bigint, app_version varchar(50), category varchar(50), device_info varchar(120), content longtext, status enum ('IN_PROGRESS','NEW','RESOLVED'), primary key (id)) engine=InnoDB;
create table journey (date date, id integer not null auto_increment, schedule_id integer, created_at datetime(6), place_id bigint, updated_at datetime(6), user_id bigint not null, body varchar(255), location varchar(255), mood_label varchar(255), title varchar(255), weather_label varchar(255), primary key (id)) engine=InnoDB;
create table journey_photos (journey_id integer not null, photo_url varchar(255)) engine=InnoDB;
create table media_objects (created_at datetime(6) not null, deleted_at datetime(6), id bigint not null auto_increment, size bigint not null, updated_at datetime(6), media_key varchar(512) not null, content_type varchar(255), original_name varchar(255), owner_id varchar(255) not null, ref_id varchar(255), ref_type varchar(255), category enum ('JOURNEY_IMAGE','PROFILE_IMAGE','REVIEW_IMAGE') not null, primary key (id)) engine=InnoDB;
create table place_descriptions (place_id varchar(16) not null, short_desc_1 tinytext, short_desc_2 tinytext, primary key (place_id)) engine=InnoDB;
create table place_features (adventure float(53), conf_adventure float(53), conf_culture float(53), conf_nature_healing float(53), conf_quiet float(53), conf_sociality float(53), conf_spirituality float(53), culture float(53), n_blogs integer, n_reviews integer, nature_healing float(53), quiet float(53), sociality float(53), spirituality float(53), link_id bigint not null, updated_at datetime(6), method_ver varchar(255), primary key (link_id)) engine=InnoDB;
create table place_hashtags (id bigint not null auto_increment, place_id varchar(16) not null, hashtag varchar(100) not null, primary key (id)) engine=InnoDB;
create table place_kakao_links (kakao_mapx float(53), kakao_mapy float(53), created datetime(6) not null, id bigint not null, place_url varchar(512), title varchar(255) not null, primary key (id)) engine=InnoDB;
create table place_simple_tags (id bigint not null auto_increment, place_id varchar(16) not null, tag varchar(100) not null, primary key (id)) engine=InnoDB;
create table place_star_ratings (rating float(53), link_id bigint not null, updated_at datetime(6), source varchar(255), primary key (link_id)) engine=InnoDB;
create table place_trait_snapshots (a_score float(53), crowdness float(53), d_score float(53), noise float(53), p_score float(53), sociality float(53), snapshot_at datetime(6), cat3 varchar(16) not null, cat3name varchar(255), hashtags tinytext, short_desc1 tinytext, short_desc2 tinytext, simple_tags tinytext, primary key (cat3)) engine=InnoDB;
create table place_traits (a_score float(53), crowdness float(53), d_score float(53), del_state integer, noise float(53), p_score float(53), sociality float(53), place_id varchar(16) not null, name varchar(200) not null, hash1 varchar(255), hash2 varchar(255), hash3 varchar(255), location_type varchar(255), short_descript1 varchar(255), short_descript2 varchar(255), simple_tag1 varchar(255), simple_tag2 varchar(255), simple_tag3 varchar(255), primary key (place_id)) engine=InnoDB;
create table places (areacode integer, l_dong_regn_cd integer, l_dong_signgu_cd integer, mapx float(53), mapy float(53), sigungucode integer, ugc_count integer not null, contentid bigint not null, createdtime datetime(6), modifiedtime datetime(6), zipcode varchar(20), tel varchar(100), addr1 varchar(255), addr2 varchar(255), cat1 varchar(255), cat2 varchar(255), cat3 varchar(255), contenttypeid varchar(255), firstimage varchar(255), firstimage2 varchar(255), mlevel varchar(255), title varchar(255), search_text LONGTEXT, seed_emotion json, ugc_emotion json, primary key (contentid)) engine=InnoDB;
create table refresh_token (created_at datetime(6) not null, expires_at datetime(6) not null, id bigint not null auto_increment, revoked_at datetime(6), user_id bigint not null, token_hash varchar(64) not null, primary key (id)) engine=InnoDB;
create table schedule (date_from date, date_to date, schedule_id integer not null auto_increment, created_at datetime(6), updated_at datetime(6), user_id bigint not null, title varchar(100), content varchar(1000), primary key (schedule_id)) engine=InnoDB;
create table users (age integer, agree_marketing bit, agree_privacy bit, agree_tos bit, created_at datetime(6), id bigint not null auto_increment, marketing_agreed_at datetime(6), privacy_agreed_at datetime(6), tos_agreed_at datetime(6), updated_at datetime(6), provider varchar(20), role varchar(20) not null, social_id varchar(191), email varchar(255), image_url varchar(255), marketing_version varchar(255), name varchar(255), nickname varchar(255), password varchar(255), privacy_version varchar(255), tos_version varchar(255), travel_type varchar(255), username varchar(255), age_group enum ('OVER14','UNDER14'), gender enum ('FEMALE','MALE','OTHER'), primary key (id)) engine=InnoDB;
alter table bookmarks add constraint UKk1k57s35xli8cwue7u9l4dnhx unique (user_id, content_id);
alter table card_reaction add constraint uk_card_reaction_card_user_type unique (card_id, user_id, reaction_type);
alter table collection_items add constraint UK9io6dptmsfqnrumptrwye63lm unique (user_id, collection_id, content_id);
alter table collections add constraint UK9jlux1cwd4hfslei7lc96f29d unique (user_id, name);
create index idx_media_owner on media_objects (owner_id);
create index idx_media_ref on media_objects (ref_type, ref_id);
alter table media_objects add constraint UK3pkjswl54cvrded30nci3u45t unique (media_key);
create index idx_ph_place on place_hashtags (place_id);
create index idx_ph_hashtag on place_hashtags (hashtag);
create index idx_place_kakao_created on place_kakao_links (created);
create index idx_pst_place on place_simple_tags (place_id);
create index idx_pst_tag on place_simple_tags (tag);
create index idx_refresh_token_user_id on refresh_token (user_id);
create index idx_refresh_token_expires_at on refresh_token (expires_at);
alter table refresh_token add constraint uk_refresh_token_token_hash unique (token_hash);
alter table users add constraint uk_users_provider_social_id unique (provider, social_id);
alter table users add constraint UK6dotkott2kjsp8vw4d0m25fb7 unique (email);
alter table bookmarks add constraint FKdbsho2e05w5r13fkjqfjmge5f foreign key (user_id) references users (id) on delete cascade;
alter table collection_items add constraint FKrkp5wpkksx5aqex6v4qnq9912 foreign key (collection_id) references collections (id) on delete cascade;
alter table collection_items add constraint FKqbqdudvmw7hwi6ijdfg2vtrq4 foreign key (user_id) references users (id) on delete cascade;
alter table collections add constraint FKn7pdedyqaiddr0uxdj603my7d foreign key (user_id) references users (id) on delete cascade;
alter table feedback add constraint FKpwwmhguqianghvi1wohmtsm8l foreign key (user_id) references users (id) on delete set null;
alter table journey add constraint FKk0vc19jo5wygypce9f3okcvvs foreign key (schedule_id) references schedule (schedule_id) on delete cascade;
alter table journey add constraint FK9xglfr1fkvuoypqh75fgxju5o foreign key (user_id) references users (id) on delete cascade;
alter table journey_photos add constraint FKqanwlnup01qpasii1iggj7s9x foreign key (journey_id) references journey (id);
alter table schedule add constraint FKdn5svbxyacce1gpfiawk7iqtc foreign key (user_id) references users (id) on delete cascade;
