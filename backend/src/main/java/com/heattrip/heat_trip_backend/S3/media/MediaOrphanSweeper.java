package com.heattrip.heat_trip_backend.S3.media;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;

/**
 * 올려 놓고 글을 안 쓴 사진·영상을 야간에 거둔다 — 이슈 #429.
 *
 * <p>업로드가 글보다 먼저라(앱이 사진을 올리고 나서 글을 보낸다) 글을 안 쓰고 나간 사람의
 * 파일이 {@code ref_type IS NULL} 인 채로 남는다. 안 거두면 버킷이 조용히 자란다.
 *
 * <h2>이 코드가 같은 DB 를 향해 동시에 두 번 실행돼도 결과가 같다 (#86 원칙 2)</h2>
 * <p>{@link MediaService#sweepOrphans} 는 "안 붙은 채 {@code ttl} 보다 오래된 것" 을 읽어
 * 행과 S3 객체를 지운다. 두 인스턴스가 같은 행을 잡아도 {@code deleteAllInBatch} 는 없는
 * 행에 0 을 주고 S3 {@code deleteObjects} 는 없는 키에도 성공을 준다. 남는 것은 새벽 4:10 의
 * 잠금 경합과 로그 두 줄이다. 멱등하다.
 *
 * <h2>{@code ttl} 이 하루인 이유</h2>
 * <p>글쓰기 화면을 열어 둔 채 하루를 넘기는 사람은 없다. 더 짧으면 저녁에 올려 두고 아침에
 * 마저 쓰는 사람의 사진이 사라진다. 설정({@code media.orphan-ttl-hours})으로 뺐다.
 *
 * <p>정리 자체는 서비스가 하고 여기는 시각만 정한다 — {@code RefreshTokenPurgeScheduler} 와
 * 같은 모양이다. 그래야 고정 {@link Clock} 으로 경계를 벽시계 없이 잰다.
 */
@Component
public class MediaOrphanSweeper {

    private static final Logger log = LoggerFactory.getLogger(MediaOrphanSweeper.class);

    private final MediaService media;
    private final Clock clock;
    private final Duration ttl;

    public MediaOrphanSweeper(MediaService media,
                              Clock clock,
                              @Value("${media.orphan-ttl-hours:24}") long ttlHours) {
        this.media = media;
        this.clock = clock;
        this.ttl = Duration.ofHours(ttlHours);
    }

    @Scheduled(cron = "${media.orphan-sweep-cron:0 10 4 * * *}", zone = "Asia/Seoul")
    public void sweep() {
        int swept = media.sweepOrphans(cutoff());
        if (swept > 0) {
            log.info("[media] 붙지 않은 채 {} 시간 지난 미디어 {}건을 거뒀다", ttl.toHours(), swept);
        }
    }

    /** 이 시각보다 먼저 올라온 것이 대상이다. 테스트가 같은 계산을 쓰게 밖에 둔다. */
    public Instant cutoff() {
        return clock.instant().minus(ttl);
    }
}
