package com.heattrip.heat_trip_backend.social.dto;

import java.util.List;
import java.util.Map;

/**
 * "함께" 피드에 노출되는 카드 응답 DTO.
 *
 * @param handle      표시 이름. null이면 프론트에서 "익명"으로 렌더링.
 * @param moodKey     6개 SSOT 한국어 무드 키.
 * @param createdAt   ISO-8601 문자열.
 * @param reactions    타입별 카운트 {SAME, CHEER, CALM}.
 * @param myReactions  현재 사용자가 누른 리액션 타입 목록.
 * @param commentCount 이 카드에 달린 댓글 수.
 */
public record CardDto(
        Long id,
        String handle,
        String moodKey,
        String placeName,
        String body,
        String createdAt,
        Map<String, Integer> reactions,
        List<String> myReactions,
        int commentCount
) {}
