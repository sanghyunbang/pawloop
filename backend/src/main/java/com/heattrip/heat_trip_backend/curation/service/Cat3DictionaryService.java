// src/main/java/com/heattrip/heat_trip_backend/curation/service/Cat3DictionaryService.java
package com.heattrip.heat_trip_backend.curation.service;

import com.heattrip.heat_trip_backend.curation.repository.PlaceTraitRepository;
import com.opencsv.CSVReader;
import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Service;

import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

/**
 * "한글 라벨 → CAT3" + "CAT3 → 한글 대표명" 사전 서비스
 *
 * - DB(place_traits)와 CSV(curation/cat3_traits.csv)를 로드하여
 *   라벨→코드(검색/해석용), 코드→대표명(표시용)을 메모리에 캐시한다.
 * - 코드/라벨 정규화(공백 제거/대문자/trim)로 매칭 실패를 줄인다.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class Cat3DictionaryService {

    private final PlaceTraitRepository traitRepo;

    /** 라벨 → 코드(동의어 포함 가능; 다대다) */
    private final Map<String, Set<String>> labelToCat3 = new ConcurrentHashMap<>();
    private final Map<String, Set<String>> normLabelToCat3 = new ConcurrentHashMap<>();

    /** 코드 → 대표명(표시용; 한 코드에 대해 일관된 이름 하나만 사용) */
    private final Map<String, String> codeToName = new ConcurrentHashMap<>();

    @PostConstruct
    public void load() {
        int fromDb  = loadFromDb();
        int fromCsv = loadFromCsvIfExists("curation/cat3_traits.csv");
        log.info("Cat3Dictionary loaded: {} pairs(DB) + {}(CSV); codeToName size={}",
                fromDb, fromCsv, codeToName.size());
    }

    /** DB(place_traits)에서 (label, cat3) 페어 로드 */
    private int loadFromDb() {
        int c = 0;
        for (Object[] row : traitRepo.findAllDistinctPairs()) {
            String label = safeTrim(row[0]);                  // 사람이 보는 이름(라벨)
            String cat3  = normalizeCode(safeTrim(row[1]));   // CAT3 코드
            if (label.isEmpty() || cat3.isEmpty()) continue;

            // ① 라벨→코드 (검색/해석용)
            putLabelToCode(label, cat3);

            // ② 코드→대표명 (표시용) — 최초 한 번만 고정(덮어쓰지 않음)
            codeToName.putIfAbsent(cat3, label);
            c++;
        }
        return c;
    }

    /** CSV(curation/cat3_traits.csv)로 보강: 헤더는 CAT3 + (이름/name/label)를 허용 */
    private int loadFromCsvIfExists(String classpathCsv) {
        var res = new ClassPathResource(classpathCsv);
        if (!res.exists()) {
            log.warn("CSV not found on classpath: {}", classpathCsv);
            return 0;
        }
        int addedPairs = 0;
        try (var reader = new CSVReader(
                new InputStreamReader(res.getInputStream(), StandardCharsets.UTF_8))) {

            String[] header = reader.readNext();
            if (header == null) return 0;

            int cat3Idx = -1, nameIdx = -1;
            for (int i = 0; i < header.length; i++) {
                String h = safeTrim(header[i]);
                if (h.equalsIgnoreCase("CAT3")) cat3Idx = i;
                if (h.equalsIgnoreCase("이름") || h.equalsIgnoreCase("name") || h.equalsIgnoreCase("label")) nameIdx = i;
            }
            if (cat3Idx < 0 || nameIdx < 0) {
                log.warn("CSV header not recognized. Need columns: CAT3 & (이름/name/label)");
                return 0;
            }

            String[] row;
            while ((row = reader.readNext()) != null) {
                if (row.length <= Math.max(cat3Idx, nameIdx)) continue;
                String cat3  = normalizeCode(safeTrim(row[cat3Idx]));
                String label = safeTrim(row[nameIdx]);
                if (cat3.isEmpty() || label.isEmpty()) continue;

                // ① 라벨→코드 (중복 체크)
                boolean exists = labelToCat3.getOrDefault(label, Set.of()).contains(cat3);
                if (!exists) {
                    putLabelToCode(label, cat3);
                    addedPairs++;
                }

                // ② 코드→대표명 (표시용) — 기본은 최초 고정.
                codeToName.putIfAbsent(cat3, label);
            }
        } catch (Exception e) {
            log.warn("CSV load failed: {}", e.toString());
        }
        return addedPairs;
    }

    /** 라벨 → 코드 삽입 (원형 라벨/정규화 라벨 모두 보강) */
    private void putLabelToCode(String label, String cat3) {
        labelToCat3.computeIfAbsent(label, k -> new HashSet<>()).add(cat3);
        normLabelToCat3.computeIfAbsent(normalizeLabel(label), k -> new HashSet<>()).add(cat3);
    }

    /** 라벨 정규화: null-safe + 공백 제거 */
    private static String normalizeLabel(String s) {
        return s == null ? "" : s.replace(" ", "");
    }

    /** 코드 정규화: null-safe + trim + upper-case */
    private static String normalizeCode(String s) {
        return s == null ? "" : s.trim().toUpperCase();
    }

    /** null-safe trim */
    private static String safeTrim(Object o) {
        return o == null ? "" : String.valueOf(o).trim();
    }

    /** 라벨 목록 → CAT3 코드 집합 (정확/정규화 매칭 모두 시도) */
    public Set<String> resolveCat3Codes(Collection<String> labels) {
        if (labels == null || labels.isEmpty()) return Set.of();
        Set<String> out = new HashSet<>();
        for (String raw : labels) {
            if (raw == null) continue;
            String trimmed = raw.trim();
            var exact = labelToCat3.get(trimmed);
            if (exact != null) out.addAll(exact);
            var norm = normLabelToCat3.get(normalizeLabel(trimmed));
            if (norm != null) out.addAll(norm);
        }
        return out;
    }

    /** 코드 → 대표명 (없으면 null) */
    public String getNameForCat3(String code) {
        if (code == null) return null;
        return codeToName.get(normalizeCode(code)); // 정규화 조회
    }
}
