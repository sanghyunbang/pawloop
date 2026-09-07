package com.heattrip.heat_trip_backend.user;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import jakarta.annotation.PostConstruct;

import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;

/**
 * 시군구 250 줄 — 이슈 #342.
 *
 * <h2>서버가 표를 들고 있는 이유</h2>
 * <p>사용자가 고른 것은 <b>행정동</b>(열 자리)인데, 서버가 쓰는 단위는 <b>시군구</b>(앞 다섯
 * 자리)다. 커뮤니티의 "우리 동네" 가 구(區) 단위이고 글 카드에 보이는 것도 "성동구" 다.
 *
 * <p>그 이름을 <b>앱이 보내 준 문자열로 쓰지 않는다.</b> 그러면 아무나 자기 동네를 "청와대"
 * 라고 적어 글 카드에 띄울 수 있다. 코드만 받고 이름은 여기서 붙인다 — 동시에 이 표가
 * <b>코드 검증</b>이기도 하다. 목록에 없는 코드는 400 이다.
 *
 * <h2>행정동 3,516 줄은 왜 없나</h2>
 * <p>서버가 동 이름을 쓸 일이 없다. 글 카드는 구까지만 보여 주고(그 아래는 사는 곳을
 * 좁힌다), 지도의 중심 좌표는 앱이 자기 자산에서 읽는다. <b>서버는 좌표를 받지도 저장하지도
 * 않는다</b> — 그것이 #235 A안의 선이다.
 *
 * <h2>출처 (CC BY 4.0 — 지우면 안 된다)</h2>
 * <p>원자료는 통계청 SGIS 행정동 경계(공공누리 제1유형), 가공본은
 * <a href="https://github.com/vuski/admdongkor">vuski/admdongkor</a> 이고 CC BY 4.0 이다.
 * 파생물에도 출처 표시 의무가 남으므로 {@code data/sigungu.json} 의 {@code source} 필드와
 * 앱의 동네 고르기 화면에 함께 적혀 있다.
 */
@Component
public class NeighborhoodCatalog {

    /** 행정동 코드의 길이. 통계청 {@code adm_cd2} 가 열 자리다. */
    public static final int CODE_LENGTH = 10;

    /** 그중 앞 다섯 자리가 시군구다. */
    public static final int SGG_LENGTH = 5;

    private static final String RESOURCE = "data/sigungu.json";

    private final ObjectMapper mapper;

    /** 시군구 코드 → 시도명·시군구명. 읽기만 하므로 불변으로 둔다. */
    private Map<String, Sigungu> bySgg = Map.of();

    public NeighborhoodCatalog(ObjectMapper mapper) {
        this.mapper = mapper;
    }

    /**
     * 시군구 하나. {@code code} 는 다섯 자리다.
     *
     * @param code 시군구 코드 (예: {@code 11200})
     * @param sido 시도명 (예: {@code 서울특별시})
     * @param name 시군구명 (예: {@code 성동구}) — 글 카드에 보이는 단위다
     */
    public record Sigungu(String code, String sido, String name) {
    }

    @PostConstruct
    void load() {
        Map<String, Sigungu> loaded = new LinkedHashMap<>();
        try (InputStream in = new ClassPathResource(RESOURCE).getInputStream()) {
            JsonNode root = mapper.readTree(new String(in.readAllBytes(), StandardCharsets.UTF_8));
            for (JsonNode row : root.path("sigungu")) {
                String code = row.path("code").asText(null);
                if (code == null || code.length() != SGG_LENGTH) {
                    continue;
                }
                loaded.put(code, new Sigungu(code, row.path("sido").asText(""), row.path("name").asText("")));
            }
        } catch (IOException e) {
            // 부팅을 멈춘다. 표가 없으면 동네를 고를 수도 검증할 수도 없는데, 그 상태로 뜨면
            // 모든 동네 저장이 400 이 되고 원인은 로그 한 줄뿐이다.
            throw new UncheckedIOException("시군구 표(" + RESOURCE + ")를 읽지 못했다", e);
        }
        if (loaded.isEmpty()) {
            throw new IllegalStateException("시군구 표가 비어 있다 — " + RESOURCE);
        }
        bySgg = Map.copyOf(loaded);
    }

    /** 표에 있는 시군구 수. 테스트가 "다 읽었나" 를 이걸로 본다. */
    public int size() {
        return bySgg.size();
    }

    /**
     * 행정동 코드가 우리가 아는 시군구에 속하는가.
     *
     * <p>동 자체는 검증하지 않는다 — 3,516 줄을 서버가 들고 있을 이유가 없고, 틀린 동 코드가
     * 만드는 최악이 "우리 동네에 안 잡힌다" 라서다. 반대로 <b>시군구를 검증하지 않으면</b>
     * 아무 문자열이나 저장돼 커뮤니티 필터가 조용히 아무것도 안 준다.
     */
    public Optional<Sigungu> find(String neighborhoodCode) {
        if (neighborhoodCode == null || neighborhoodCode.length() != CODE_LENGTH) {
            return Optional.empty();
        }
        return Optional.ofNullable(bySgg.get(neighborhoodCode.substring(0, SGG_LENGTH)));
    }

    /** 그 코드가 속한 시군구의 앞자리. 커뮤니티가 {@code LIKE '11200%'} 로 쓴다. */
    public static String sggPrefixOf(String neighborhoodCode) {
        return neighborhoodCode == null || neighborhoodCode.length() < SGG_LENGTH
                ? null
                : neighborhoodCode.substring(0, SGG_LENGTH);
    }
}
