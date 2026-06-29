package com.heattrip.heat_trip_backend.explore.dto;

import java.time.LocalDateTime;
import java.util.List;
import lombok.*;

@Getter @Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class PlaceSummaryDto {
    private Long contentid;
    private String title;

    private Integer contentTypeId; // 콘텐츠 타입 ID [0831 추가]

    // Flutter와 통일
    private String addr1;
    private String addr2;
    private String firstimage2;

    // 기존
    private String firstimage;
    private Integer areacode;
    private Integer sigungucode;
    private LocalDateTime createdtime;

    // ▼ 스냅샷 파생 필드(LEFT JOIN으로 가져옴)
    private String cat3;         // 예: A02010400
    private String cat3Name;     // 예: 고택
    private String shortDesc1;   // 간단 설명 1
    private String shortDesc2;   // 간단 설명 2

    @Builder.Default
    private List<String> hashtags = List.of();    // ["#고즈넉함", "#한옥정취", ...]
    @Builder.Default
    
    private List<String> simpleTags = List.of();  // ["전통","감성","산책"]

    //[!] JPQL constructor expression용 기존 생성자 유지 (절대 바꾸지 마세요)
    //Offset 경로(JPQL): 위 6-인자 생성자를 그대로 쓰므로 영향 없음(추가 필드는 null/빈리스트로 남음).
    //Cursor 경로(네이티브+MapStruct): no-args + setter로 추가 필드가 채워짐.

    public PlaceSummaryDto(Long contentid, String title, String firstimage,
                           Integer areacode, Integer sigungucode, LocalDateTime createdtime) {
        this.contentid   = contentid;
        this.title       = title;
        this.firstimage  = firstimage;
        this.areacode    = areacode;
        this.sigungucode = sigungucode;
        this.createdtime = createdtime;
    }
}
