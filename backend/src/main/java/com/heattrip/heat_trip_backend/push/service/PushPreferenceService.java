package com.heattrip.heat_trip_backend.push.service;

import com.heattrip.heat_trip_backend.push.entity.PushPreference;
import com.heattrip.heat_trip_backend.push.repository.PushPreferenceRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Collection;
import java.util.List;
import java.util.Set;

/**
 * "전체 끄기" — 사용자별 알림 설정 (이슈 #83). 행이 없으면 켜진 것이다.
 */
@Service
@RequiredArgsConstructor
public class PushPreferenceService {

    private final PushPreferenceRepository preferences;

    @Transactional(readOnly = true)
    public boolean isEnabled(long userId) {
        return preferences.findById(userId).map(PushPreference::isEnabled).orElse(true);
    }

    @Transactional
    public boolean setEnabled(long userId, boolean enabled) {
        PushPreference row = preferences.findById(userId)
                .orElseGet(() -> PushPreference.builder().userId(userId).build());
        row.setEnabled(enabled);
        preferences.save(row);
        return enabled;
    }

    /** 주어진 사람들 중 알림을 켜 둔 사람만. 순서는 들어온 대로다. */
    @Transactional(readOnly = true)
    public List<Long> onlyEnabled(Collection<Long> userIds) {
        if (userIds.isEmpty()) {
            return List.of();
        }
        Set<Long> disabled = Set.copyOf(preferences.disabledAmong(userIds));
        return userIds.stream().filter(id -> !disabled.contains(id)).toList();
    }

    /** 탈퇴 — 행을 지운다. */
    @Transactional
    public void deleteOf(long userId) {
        preferences.deleteById(userId);
    }
}
