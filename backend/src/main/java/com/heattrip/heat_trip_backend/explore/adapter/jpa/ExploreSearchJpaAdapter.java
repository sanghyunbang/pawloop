package com.heattrip.heat_trip_backend.explore.adapter.jpa;

import com.heattrip.heat_trip_backend.explore.dto.PageResponse;
import com.heattrip.heat_trip_backend.explore.dto.PlaceSummaryDto;
import com.heattrip.heat_trip_backend.explore.dto.search.PlaceSearchCond;
import com.heattrip.heat_trip_backend.explore.port.ExploreSearchPort;
import jakarta.persistence.EntityManager;
import jakarta.persistence.Query;
import org.springframework.stereotype.Component;

import java.sql.Timestamp;
import java.time.LocalDateTime;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;

@Component
public class ExploreSearchJpaAdapter implements ExploreSearchPort {

    private static final Pattern BOOLEAN_RESERVED = Pattern.compile("[+\\-<>()~*\"@]+");

    private final EntityManager em;

    public ExploreSearchJpaAdapter(EntityManager em) {
        this.em = em;
    }

    @Override
    public PageResponse<PlaceSummaryDto> search(PlaceSearchCond c) {
        String keyword = normalizeFullTextKeyword(c.q());
        Map<String, Object> params = new LinkedHashMap<>();

        StringBuilder from = new StringBuilder("""
            FROM places p
            LEFT JOIN place_trait_snapshots s ON s.cat3 = p.cat3
            WHERE 1=1
            """);

        if (keyword != null) {
            from.append("\n  AND MATCH(p.search_text) AGAINST (:keyword IN BOOLEAN MODE)");
            params.put("keyword", keyword);
        }

        if (c.contentTypeId() != null) {
            from.append("\n  AND p.contenttypeid = :contentTypeId");
            params.put("contentTypeId", String.valueOf(c.contentTypeId()));
        }

        if (c.cat3() != null && !c.cat3().isEmpty()) {
            appendInClause(from, params, "p.cat3", "cat3", c.cat3());
        }

        if (c.emotionCategoryId() != null) {
            from.append("""

                  AND EXISTS (
                      SELECT 1
                      FROM cat3_category_mapping m
                      WHERE m.category_id = :emotionCategoryId
                        AND m.cat3_code = p.cat3
                  )
                """);
            params.put("emotionCategoryId", c.emotionCategoryId());
        }

        String selectSql = """
            SELECT
                p.contentid,
                p.title,
                p.firstimage,
                p.areacode,
                p.sigungucode,
                p.createdtime,
                p.addr1,
                p.addr2,
                p.firstimage2,
                p.contenttypeid,
                p.cat3,
                s.cat3name,
                s.short_desc1,
                s.short_desc2
            """ + from + buildOrderBy(c.sort());

        Query query = em.createNativeQuery(selectSql);
        bindParameters(query, params);
        query.setFirstResult(c.offset());
        query.setMaxResults(c.limit());

        @SuppressWarnings("unchecked")
        List<Object[]> rows = query.getResultList();

        String countSql = "SELECT COUNT(*) " + from;
        Query countQuery = em.createNativeQuery(countSql);
        bindParameters(countQuery, params);
        long total = ((Number) countQuery.getSingleResult()).longValue();

        List<PlaceSummaryDto> content = rows.stream()
            .map(this::toDto)
            .toList();

        int page = c.page() == null ? 0 : c.page();
        int size = c.size() == null ? 20 : c.size();
        boolean last = ((long) (page + 1) * size) >= total;

        return new PageResponse<>(content, page, size, total, last);
    }

    private void appendInClause(StringBuilder sql, Map<String, Object> params, String column, String prefix, List<String> values) {
        sql.append("\n  AND ").append(column).append(" IN (");
        for (int i = 0; i < values.size(); i++) {
            if (i > 0) {
                sql.append(", ");
            }
            String key = prefix + i;
            sql.append(":").append(key);
            params.put(key, values.get(i));
        }
        sql.append(")");
    }

    private void bindParameters(Query query, Map<String, Object> params) {
        params.forEach(query::setParameter);
    }

    private String buildOrderBy(String sort) {
        if (sort == null) {
            sort = "";
        }
        return switch (sort) {
            case "title" -> "\n ORDER BY p.title ASC, p.contentid DESC";
            case "recent" -> "\n ORDER BY p.modifiedtime DESC, p.contentid DESC";
            case "random" -> "\n ORDER BY RAND()";
            default -> "\n ORDER BY p.contentid DESC";
        };
    }

    private PlaceSummaryDto toDto(Object[] row) {
        PlaceSummaryDto dto = new PlaceSummaryDto(
            toLong(row[0]),
            toString(row[1]),
            toString(row[2]),
            toInteger(row[3]),
            toInteger(row[4]),
            toLocalDateTime(row[5])
        );
        dto.setAddr1(toString(row[6]));
        dto.setAddr2(toString(row[7]));
        dto.setFirstimage2(toString(row[8]));
        dto.setContentTypeId(parseIntOrNull(toString(row[9])));
        dto.setCat3(toString(row[10]));
        dto.setCat3Name(toString(row[11]));
        dto.setShortDesc1(toString(row[12]));
        dto.setShortDesc2(toString(row[13]));
        dto.setHashtags(Collections.emptyList());
        dto.setSimpleTags(Collections.emptyList());
        return dto;
    }

    private String normalizeFullTextKeyword(String q) {
        if (q == null || q.isBlank()) {
            return null;
        }
        String sanitized = BOOLEAN_RESERVED.matcher(q.trim()).replaceAll(" ");
        sanitized = sanitized.replaceAll("\\s+", " ").trim();
        return sanitized.isEmpty() ? null : sanitized;
    }

    private String toString(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private Integer toInteger(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Number number) {
            return number.intValue();
        }
        try {
            return Integer.parseInt(String.valueOf(value));
        } catch (NumberFormatException e) {
            return null;
        }
    }

    private Long toLong(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Number number) {
            return number.longValue();
        }
        return Long.parseLong(String.valueOf(value));
    }

    private LocalDateTime toLocalDateTime(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof LocalDateTime localDateTime) {
            return localDateTime;
        }
        if (value instanceof Timestamp timestamp) {
            return timestamp.toLocalDateTime();
        }
        return LocalDateTime.parse(String.valueOf(value).replace(" ", "T"));
    }

    private Integer parseIntOrNull(String s) {
        if (s == null) {
            return null;
        }
        try {
            return Integer.parseInt(s);
        } catch (NumberFormatException e) {
            return null;
        }
    }
}
