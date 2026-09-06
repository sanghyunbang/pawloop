package com.heattrip.heat_trip_backend.place.layer;

import lombok.Getter;
import lombok.Setter;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/**
 * 공공데이터 레이어(동물병원·펫샵·산책로) 적재 설정 — 이슈 #291.
 *
 * <p>KTO 카탈로그({@code app.kto.*})와 따로 둔 이유: 갱신 주기가 다르다. KTO 는 매일이고
 * 여기는 <b>월 1회</b>다. 인허가 데이터는 개·폐업이 느리게 바뀌고, 두루누비 코스는 거의
 * 정적이다. 매일 받으면 예산만 태운다.
 */
@Component
@ConfigurationProperties(prefix = "app.place.layer")
@Getter
@Setter
public class LayerCatalogProperties {

    /**
     * 월 1회 적재 잡과 기동 시 예열을 켜는 스위치. <b>테스트에서는 꺼져 있다</b>
     * ({@code application-test.properties}) — 켜져 있으면 CI 가 뜰 때마다 공공데이터를 부른다.
     */
    private boolean refreshEnabled = true;

    /**
     * 기동 직후 레이어 한 벌이 <b>없으면</b> 뒤에서 받아 둔다. 없으면 다음 달 1일까지
     * 병원·펫샵·산책로 칩이 빈다 — 배포한 날 그것을 겪지 않으려는 스위치다.
     */
    private boolean warmUpOnStart = true;

    /** 이 일수보다 오래된 한 벌은 다시 받아 본다. 만료가 아니다 — 못 받으면 옛 것을 계속 준다. */
    private int refreshDays = 30;

    /** 인허가 API 한 페이지 크기. 가이드 상한이 100 이다. */
    private int localdataPageSize = 100;

    /** 인허가 API 에서 업종 하나당 넘기지 않는 페이지 수 — 예산의 이중 방어. */
    private int localdataMaxPages = 200;

    /** 두루누비 코스 목록 한 페이지 크기. */
    private int durunubiPageSize = 100;

    /** 두루누비 코스 목록에서 넘기지 않는 페이지 수. */
    private int durunubiMaxPages = 50;

    /** 한 번의 적재에서 받는 GPX 파일 수의 상한. 두루누비 걷기길은 2,000 코스 안팎이다. */
    private int gpxMaxPerRun = 3000;

    /**
     * 경로 하나에 남기는 점의 상한. GPX 원본은 코스 하나에 수천 점이라, 그대로 두면
     * 산책로 하나가 수백 KB 다. 지도 폴리라인은 300 점이면 형태가 그대로다.
     */
    private int gpxMaxPoints = 300;
}
