# 3. Import 중 Read Latency 측정

이 테스트의 목적은 Tour import가 실행되는 동안 기존 조회가 얼마나 느려지는지 수치화하는 것이다.

단순히 "문제가 생기나?"보다 "얼마나 느려지나?"를 보는 테스트다.

## 핵심 질문

- import가 없을 때 read latency는 얼마인가?
- import 중 read latency는 얼마나 증가하는가?
- p95/p99가 사용자에게 문제가 될 정도로 증가하는가?
- read 실패나 timeout이 발생하는가?
- import 데이터 크기에 따라 latency가 어떻게 변하는가?

## 테스트 시나리오

최소 3개 시나리오를 비교한다.

| 시나리오 | 설명 |
|---|---|
| Baseline | import 없이 read만 수행 |
| During Import | import write와 read를 동시에 수행 |
| After Import | import 완료 후 read만 수행 |

이렇게 나눠야 import가 read latency에 준 영향을 비교할 수 있다.

## 측정 대상

read는 실제 사용자가 많이 호출하는 경로를 기준으로 선택한다.

후보:

- `PlaceRepository.findById()`
- `ExplorePlaceRepository.findSummaries()`
- `PlaceQueryRepository.findNextByCursor()`
- `ExploreService.list()`
- `ExploreService.scroll()`

학습 단계에서는 repository 직접 호출로 시작하고, 이후 service 호출로 확장하는 것을 추천한다.

## 왜 p95/p99가 중요한가

평균 latency는 전체 경향을 보여주지만, 사용자 경험은 느린 요청에 크게 좌우된다.

예를 들어 100개 요청 중 95개가 30ms이고 5개가 3초라면 평균은 생각보다 낮게 보일 수 있다. 하지만 사용자는 3초짜리 요청을 문제로 느낀다.

그래서 최소한 아래를 기록한다.

- avg
- p50
- p95
- p99
- max
- failure count

## 테스트 데이터 크기

처음부터 너무 크게 시작하지 말고 단계적으로 늘린다.

| 단계 | 초기 데이터 | import 데이터 |
|---|---:|---:|
| small | 1,000 | 1,000 |
| medium | 10,000 | 10,000 |
| large | 50,000 | 50,000 |

작은 데이터셋에서 테스트 구조가 맞는지 확인한 뒤, 점점 늘려야 병목을 해석하기 쉽다.

## JUnit 예시: Baseline과 During Import 비교

```java
package com.heattrip.heat_trip_backend.tour.performance;

import com.heattrip.heat_trip_backend.tour.domain.Place;
import com.heattrip.heat_trip_backend.tour.repository.PlaceRepository;
import com.heattrip.heat_trip_backend.tour.service.PlaceService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import java.util.List;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;

@SpringBootTest
class ImportReadLatencyTest {

    @Autowired
    PlaceRepository placeRepository;

    @Autowired
    PlaceService placeService;

    @Test
    @DisplayName("import 전/중 read latency를 비교한다")
    void compareReadLatencyBeforeAndDuringImport() throws Exception {
        placeRepository.saveAll(TestPlaceFactory.places(1, 10_000));
        placeRepository.flush();

        LatencyResult baseline = runReadOnlyScenario(8, 1_000);
        LatencyResult duringImport = runReadWithImportScenario(8, 1_000, 10_000);

        System.out.println("baseline=" + baseline);
        System.out.println("duringImport=" + duringImport);
    }

    private LatencyResult runReadOnlyScenario(int readerThreads, int readsPerThread) throws Exception {
        ExecutorService executor = Executors.newFixedThreadPool(readerThreads);
        CountDownLatch start = new CountDownLatch(1);
        CountDownLatch done = new CountDownLatch(readerThreads);

        LatencyRecorder latencies = new LatencyRecorder();
        AtomicInteger failures = new AtomicInteger();

        for (int t = 0; t < readerThreads; t++) {
            executor.submit(() -> {
                await(start);
                try {
                    for (int i = 0; i < readsPerThread; i++) {
                        readOne(i, latencies, failures);
                    }
                } finally {
                    done.countDown();
                }
            });
        }

        start.countDown();
        done.await(60, TimeUnit.SECONDS);
        executor.shutdownNow();

        return LatencyResult.from(readerThreads * readsPerThread, failures.get(), latencies);
    }

    private LatencyResult runReadWithImportScenario(
            int readerThreads,
            int readsPerThread,
            int importCount
    ) throws Exception {
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
                        readOne(i, latencies, failures);
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
                List<Place> updates = TestPlaceFactory.places(1, importCount).stream()
                        .peek(p -> p.setTitle("import 갱신 " + p.getContentid()))
                        .toList();
                placeService.saveInBatches(updates, 200);
            } finally {
                done.countDown();
            }
        });

        ready.await(10, TimeUnit.SECONDS);
        start.countDown();
        done.await(120, TimeUnit.SECONDS);
        executor.shutdownNow();

        return LatencyResult.from(readerThreads * readsPerThread, failures.get(), latencies);
    }

    private void readOne(int i, LatencyRecorder latencies, AtomicInteger failures) {
        long begin = System.nanoTime();
        try {
            long id = 1L + (i % 10_000);
            placeRepository.findById(id);
        } catch (Exception e) {
            failures.incrementAndGet();
        } finally {
            latencies.record(System.nanoTime() - begin);
        }
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

## LatencyResult 예시

```java
record LatencyResult(
        int totalRequests,
        int failures,
        double avgMs,
        double p50Ms,
        double p95Ms,
        double p99Ms,
        double maxMs
) {
    static LatencyResult from(int totalRequests, int failures, LatencyRecorder recorder) {
        return new LatencyResult(
                totalRequests,
                failures,
                recorder.avgMillis(),
                recorder.percentileMillis(50),
                recorder.percentileMillis(95),
                recorder.percentileMillis(99),
                recorder.maxMillis()
        );
    }
}
```

## 결과 표 예시

| 데이터 크기 | 시나리오 | read 요청 | 실패 | avg | p50 | p95 | p99 | max |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 10,000 | Baseline | 8,000 | 0 | 8ms | 5ms | 20ms | 60ms | 120ms |
| 10,000 | During Import | 8,000 | 0 | 30ms | 9ms | 180ms | 700ms | 1.8s |
| 10,000 | After Import | 8,000 | 0 | 10ms | 6ms | 25ms | 80ms | 130ms |

## 해석 방법

가능한 결론은 크게 세 가지다.

### 1. 실패도 없고 p95/p99 증가도 작다

현재 import 방식이 읽기 API에 큰 영향을 주지 않는다고 볼 수 있다. 다만 데이터 크기를 더 늘려서 다시 확인해야 한다.

### 2. 실패는 없지만 p95/p99가 크게 증가한다

기능은 깨지지 않지만 사용자 경험에 영향이 있다. import 시간대 제한, batch 크기 조정, 커넥션 풀 분리, native upsert 최적화 등을 검토한다.

### 3. 실패나 timeout이 발생한다

운영 환경에서 그대로 실행하기 위험하다. import 중복 방지, transaction 범위 축소, lock wait timeout 조정, staging table 방식 등을 검토해야 한다.

## 주의할 점

- 같은 테스트를 최소 3회 이상 반복한다.
- 첫 실행은 JVM warm-up, DB cache 영향이 있을 수 있다.
- 테스트 머신의 CPU/메모리 상태에 따라 결과가 흔들릴 수 있다.
- 결과 표에는 실행 환경을 같이 적는다.

실행 환경 예시:

```text
OS: Windows 11
JDK: 21
DB: MySQL 8.4 Docker
Dataset: places 10,000 rows
Reader threads: 8
Connection pool: Hikari default
Batch size: 200
```
