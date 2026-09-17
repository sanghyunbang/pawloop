package com.heattrip.heat_trip_backend.support;

import jakarta.persistence.Entity;
import jakarta.persistence.Table;

import org.springframework.beans.factory.config.BeanDefinition;
import org.springframework.context.annotation.ClassPathScanningCandidateComponentProvider;
import org.springframework.core.type.filter.AnnotationTypeFilter;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * <b>어느 표·엔티티가 어느 모듈의 것인가.</b>
 *
 * <p>모듈 경계를 <b>DB 쪽에서</b> 보는 검사들이 함께 쓴다 — 모듈 밖으로 나가는 FK
 * ({@code CrossModuleForeignKeysTest}) 와 모듈 밖을 조인하는 쿼리
 * ({@code CrossModuleQueryJoinsTest}). 둘이 각자 표를 분류하면 한쪽만 낡는다.
 *
 * <p>표 → 모듈은 <b>손으로 적는다.</b> 이름으로 짐작하면 틀리는 자리가 있다 —
 * {@code walk_note} 는 {@code care} 의 것이다. 엔티티 → 모듈은 반대로 <b>패키지에서 읽는다</b>:
 * 클래스가 사는 자리가 곧 소유고, 손으로 적으면 옮길 때마다 낡는다.
 */
public final class ModuleTables {

    private ModuleTables() {
    }

    private static final String ROOT = "com.heattrip.heat_trip_backend";

    /**
     * 표 → 그 표를 소유한 모듈. 엔티티의 {@code @Table(name = ...)} 과 그 클래스의 패키지에서 온 값이다.
     *
     * <p>새 표를 여기 안 적으면 그 표의 FK·조인이 <b>조용히 안 세어진다</b> — "0건" 과
     * "안 봤다" 가 구별되지 않는다. 그래서 부르는 검사가 "정본 스키마의 모든 표가 여기 있는가" 를
     * 먼저 잰다.
     */
    public static final Map<String, String> BY_TABLE = Map.ofEntries(
            Map.entry("care_item", "care"),
            Map.entry("care_log", "care"),
            Map.entry("walk_note", "care"),
            Map.entry("chat_message", "chat"),
            Map.entry("chat_message_reaction", "chat"),
            Map.entry("chat_room", "chat"),
            Map.entry("chat_room_invite", "chat"),
            Map.entry("chat_room_member", "chat"),
            Map.entry("comment", "community"),
            Map.entry("post", "community"),
            Map.entry("post_bookmark", "community"),
            Map.entry("reaction", "community"),
            Map.entry("course", "walk"),
            Map.entry("walk", "walk"),
            Map.entry("walk_dog", "walk"),
            Map.entry("weekly_insight", "walk"),
            Map.entry("crew", "crew"),
            Map.entry("crew_favor", "crew"),
            Map.entry("device_token", "push"),
            Map.entry("push_preference", "push"),
            Map.entry("dog", "dog"),
            Map.entry("family_group", "group"),
            Map.entry("kto_call_budget", "place"),
            Map.entry("pet_place_detail", "place"),
            Map.entry("place_catalog", "place"),
            Map.entry("place_cell", "place"),
            Map.entry("trail_route", "place"),
            Map.entry("media_objects", "S3"),
            Map.entry("refresh_token", "user"),
            // 인증을 마치기 전의 가입 요청(#635). users 가 아니라 여기 있는 이유는
            // V2__pending_signup.sql 의 머리말에 있다 — 요지는 "남이 내 주소로 시도만 해 놓고
            // 그 주소를 막아 두는 일" 이 없어야 한다는 것이다.
            Map.entry("pending_signup", "user"),
            // 진행 중인 비밀번호 재설정(#635 조각 ③). users 로 FK 를 안 건다 —
            // refresh_token 과 같은 판단이라 BASELINE 에도 이 표의 줄이 없다.
            Map.entry("password_reset", "user"),
            Map.entry("users", "user"),
            Map.entry("user_consent", "consent"),
            Map.entry("report", "moderation"),
            Map.entry("report_snapshot", "moderation"),
            Map.entry("user_block", "moderation"),
            Map.entry("schedule", "schedule"),
            Map.entry("schedule_exception", "schedule"));

    /** 엔티티의 단순 이름 → 모듈. 클래스가 사는 패키지에서 읽는다. */
    public static Map<String, String> byEntityName() {
        var scanner = new ClassPathScanningCandidateComponentProvider(false);
        scanner.addIncludeFilter(new AnnotationTypeFilter(Entity.class));

        Map<String, String> out = new LinkedHashMap<>();
        for (BeanDefinition definition : scanner.findCandidateComponents(ROOT)) {
            String fqcn = definition.getBeanClassName();
            if (fqcn == null || !fqcn.startsWith(ROOT + ".")) {
                continue;
            }
            String rest = fqcn.substring(ROOT.length() + 1);
            out.put(rest.substring(rest.lastIndexOf('.') + 1), rest.substring(0, rest.indexOf('.')));
        }
        return out;
    }

    /**
     * 쿼리가 부른 이름의 주인. 표 이름이면 표 지도에서, 엔티티 이름이면 패키지에서.
     *
     * @return 모르는 이름이면 {@code null} — 부르는 쪽이 그것을 어떻게 다룰지 정한다
     */
    public static String ownerOf(String name, Map<String, String> byEntityName) {
        String byTable = BY_TABLE.get(name.toLowerCase());
        return byTable != null ? byTable : byEntityName.get(name);
    }

    /** 엔티티에 {@code @Table} 이 없으면 클래스 이름이 표 이름이 된다 — 그 경우를 잇는다. */
    public static String tableNameOf(Class<?> entity) {
        Table table = entity.getAnnotation(Table.class);
        return table != null && !table.name().isBlank() ? table.name() : entity.getSimpleName();
    }
}
