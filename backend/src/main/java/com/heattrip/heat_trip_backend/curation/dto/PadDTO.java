package com.heattrip.heat_trip_backend.curation.dto;

import lombok.*;

/** 사용자 PAD 입력(-2,-1,1,2) */
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
public class PadDTO {
    private int pleasure;
    private int arousal;
    private int dominance;
}
