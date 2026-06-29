# 4. Snapshot/Search Text 전체 Update 영향 측정

이 테스트의 목적은 `TraitSnapshotService.rebuildAllSnapshots()`와 `PlaceRepository.refreshAllSearchTexts()`가 읽기 API에 주는 영향을 확인하는 것이다.

Tour import 자체보다 이 단계가 더 무거울 수 있다. 특히 `refreshAllSearchTexts()`는 `places` 전체를 update하는 native query이므로 데이터가 많아지면 lock 부담이 커질 수 있다.

## 현재 구조

`TraitSnapshotService.rebuildAllSnapshots()` 흐름:

1. `places`에서 존재하는 `cat3` 목록 수집
2. 기존 `place_trait_snapshots` 전체 삭제
3. cat3별 trait/hashtag/simple tag/description 조회
4. snapshot batch 생성
5. snapshot 저장
6. `PlaceRepository.refreshAllSearchTexts()` 호출

핵심 위험 지점:

```java
placeRepo.refreshAllSearchTexts();
```

이 쿼리는 `places` 전체 row의 `search_text`를 갱신한다.

## 핵심 질문

- snapshot rebuild 중 read API가 실패하는가?
- `refreshAllSearchTexts()` 실행 중 p95/p99 latency가 증가하는가?
- 전체 update 시간이 데이터 크기에 따라 얼마나 늘어나는가?
- update 중 다른 write 작업이 lock wait에 걸리는가?
- `place_trait_snapshots`를 delete 후 insert하는 동안 join 조회가 빈 결과를 볼 수 있는가?

## 이 테스트가 중요한 이유

Explore 조회 중 일부는 `places`와 `place_trait_snapshots`를 join한다.

예를 들어 cursor 기반 조회는 snapshot 테이블과 join한다. snapshot rebuild가 기존 snapshot을 삭제한 뒤 다시 insert하는 방식이라면, transaction 격리 수준과 호출 시점에 따라 사용자가 일시적으로 빈 결과나 이전 snapshot을 볼 가능성을 검토해야 한다.

또한 `places.search_text` 전체 update는 row lock을 많이 잡을 수 있다. 일반 select는 MVCC 덕분에 바로 막히지 않을 수 있지만, 다른 update나 locking read는 영향을 받을 수 있다.

## 테스트 시나리오

| 시나리오 | 설명 |
|---|---|
| Baseline | snapshot rebuild 없이 read만 수행 |
| During Snapshot Rebuild | `rebuildAllSnapshots()`와 read 동시 수행 |
| During Search Text Update | `refreshAllSearchTexts()`와 read 동시 수행 |
| Concurrent Write | search_text update 중 다른 write 수행 |

처음에는 `refreshAllSearchTexts()`만 따로 측정하는 것이 좋다. 전체 snapshot rebuild는 여러 작업이 섞여 있어 원인 분리가 어렵다.

## 테스트 데이터 준비

필요한 데이터:

- `places`
- trait 원본 테이블
- hashtag/simple tag/description 테이블
- `place_trait_snapshots`

학습 초기에는 snapshot 전체 흐름 대신 `places`와 `place_trait_snapshots`에 최소 데이터만 넣고 `refreshAllSearchTexts()`를 직접 호출한다.

## JUnit 예시: refreshAllSearchTexts 중 read latency

```java
package com.heattrip.heat_trip_backend.tour.performance;

import com.heattrip.heat_trip_backend.tour.repository.PlaceRepository;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest
class SearchTextUpdateLatencyTest {

    @Autowired
    PlaceRepository placeRepository;

    @Test
    @DisplayName("search_text 전체 갱신 중 read latency를 측정한다")
    void measureReadLatencyDuringRefreshAllSearchTexts() throws Exception {
        // 1. 테스트 데이터 준비
        // placeRepository.saveAll(TestPlaceFactory.places(1, 50_000));
        // snapshot 테이블 데이터도 필요하면 별도 repository 또는 SQL로 준비

        int readerThreads = 8;
        int readsPerThread = 2_000;

        ExecutorService executor = Executors.newFixedThreadPool(readerThreads + 1);
        CountDownLatch ready = new CountDownLatch(readerThreads + 1);
        CountDownLatch start = new CountDownLatch(1);
        CountDownLatch done = new CountDownLatch(readerThreads + 1);

        LatencyRecorder latencies = new LatencyRecorder();
        AtomicInteger failures = new AtomicInteger();

        for (int t = 0; t < readerThreads; t++) {
            executor.submit(() -> {
                ready.countDown();
                await(start);
                try {
                    for (int i = 0; i < readsPerThread; i++) {
                        long begin = System.nanoTime();
                        try {
                            placeRepository.findById(1L + (i % 50_000));
                        } catch (Exception e) {
                            failures.incrementAndGet();
                        } finally {
                            latencies.record(System.nanoTime() - begin);
                        }
                    }
                } finally {
                    done.countDown();
                }
            });
        }

        executor.submit(() -> {
            ready.countDown();
            await(start);
            try {
                long begin = System.nanoTime();
                int updated = placeRepository.refreshAllSearchTexts();
                long elapsedMs = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - begin);

                System.out.println("updated=" + updated);
                System.out.println("refreshAllSearchTexts elapsedMs=" + elapsedMs);
            } finally {
                done.countDown();
            }
        });

        ready.await(10, TimeUnit.SECONDS);
        start.countDown();

        boolean finished = done.await(180, TimeUnit.SECONDS);
        executor.shutdownNow();

        assertThat(finished).isTrue();

        System.out.println("failures=" + failures.get());
        System.out.println("avgMs=" + latencies.avgMillis());
        System.out.println("p95Ms=" + latencies.percentileMillis(95));
        System.out.println("p99Ms=" + latencies.percentileMillis(99));
        System.out.println("maxMs=" + latencies.maxMillis());
    }

    private static void await(CountDownLatch latch) {
        try {
            latch.await();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new RuntimeException(e);
        }
    }
}
```

## JUnit 예시: 전체 snapshot rebuild 시간 측정

```java
@Test
@DisplayName("TraitSnapshotService.rebuildAllSnapshots 소요 시간을 측정한다")
void measureSnapshotRebuildDuration() {
    long begin = System.nanoTime();

    int inserted = traitSnapshotService.rebuildAllSnapshots(1_000);

    long elapsedMs = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - begin);

    System.out.println("inserted snapshots=" + inserted);
    System.out.println("elapsedMs=" + elapsedMs);
}
```

이 테스트는 latency 측정보다 batch job 자체 성능을 보는 테스트다.

## JUnit 예시: snapshot rebuild 중 join 조회

Explore의 cursor 조회는 `places`와 `place_trait_snapshots`를 join한다. rebuild 중 join 조회 결과가 안정적인지 보고 싶다면 `PlaceQueryRepository.findNextByCursor()`를 동시에 호출한다.

```java
@Test
@DisplayName("snapshot rebuild 중 cursor 조회 결과 수와 실패 여부를 측정한다")
void readCursorDuringSnapshotRebuild() throws Exception {
    int readerThreads = 4;
    int readsPerThread = 500;

    ExecutorService executor = Executors.newFixedThreadPool(readerThreads + 1);
    CountDownLatch start = new CountDownLatch(1);
    CountDownLatch done = new CountDownLatch(readerThreads + 1);

    AtomicInteger emptyResults = new AtomicInteger();
    AtomicInteger failures = new AtomicInteger();
    LatencyRecorder latencies = new LatencyRecorder();

    for (int t = 0; t < readerThreads; t++) {
        executor.submit(() -> {
            await(start);
            try {
                for (int i = 0; i < readsPerThread; i++) {
                    long begin = System.nanoTime();
                    try {
                        List<PlaceSummaryProjection> rows = placeQueryRepository.findNextByCursor(
                                null, null, null, null, null,
                                null, null,
                                PageRequest.of(0, 20)
                        );
                        if (rows.isEmpty()) {
                            emptyResults.incrementAndGet();
                        }
                    } catch (Exception e) {
                        failures.incrementAndGet();
                    } finally {
                        latencies.record(System.nanoTime() - begin);
                    }
                }
            } finally {
                done.countDown();
            }
        });
    }

    executor.submit(() -> {
        await(start);
        try {
            traitSnapshotService.rebuildAllSnapshots(1_000);
        } finally {
            done.countDown();
        }
    });

    start.countDown();
    done.await(180, TimeUnit.SECONDS);
    executor.shutdownNow();

    System.out.println("failures=" + failures.get());
    System.out.println("emptyResults=" + emptyResults.get());
    System.out.println("p95Ms=" + latencies.percentileMillis(95));
    System.out.println("p99Ms=" + latencies.percentileMillis(99));
}
```

## 결과 표 예시

| 데이터 크기 | 시나리오 | read 요청 | 실패 | 빈 결과 | avg | p95 | p99 | max | job time |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 10,000 | baseline | 8,000 | 0 | 0 | 10ms | 35ms | 80ms | 140ms | - |
| 10,000 | refresh search_text | 8,000 | 0 | 0 | 50ms | 300ms | 1.2s | 2.5s | 18s |
| 10,000 | snapshot rebuild | 8,000 | 0 | 12 | 70ms | 450ms | 1.8s | 3.0s | 25s |

## 해석 포인트

### 실패는 없지만 p99가 튄다

일반 read는 유지되지만 tail latency가 나빠진다. 사용자 트래픽이 많은 시간에는 실행하지 않는 것이 좋다.

### 빈 결과가 발생한다

join 대상인 snapshot 테이블이 rebuild 중 비는 순간이 있을 수 있다. 이 경우 delete 후 insert 방식 대신 다음 구조를 검토한다.

- versioned snapshot table
- staging table에 먼저 생성 후 swap
- snapshot rebuild transaction 범위 조정
- read query가 이전 snapshot version을 계속 보게 하는 방식

### 전체 update 시간이 길다

`refreshAllSearchTexts()`를 batch update로 나누는 것을 검토한다.

예시 개선 방향:

```sql
UPDATE places
SET search_text = ...
WHERE contentid BETWEEN ? AND ?;
```

또는 cat3 기준으로 영향을 받은 row만 갱신한다.

```sql
UPDATE places
SET search_text = ...
WHERE cat3 IN (...);
```

## 운영 개선 방향

- snapshot rebuild를 저트래픽 시간대에 실행
- `refreshAllSearchTexts()` 전체 update를 batch update로 변경
- snapshot table을 delete 후 insert하지 않고 version 기반으로 교체
- import와 snapshot rebuild가 동시에 돌지 않도록 lock 추가
- 실행 이력 테이블에 시작/종료/성공/실패/updated row 수 기록
