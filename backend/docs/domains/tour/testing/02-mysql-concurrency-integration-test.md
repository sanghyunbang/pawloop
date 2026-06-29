# 2. MySQL 기반 동시성 통합 테스트

이 테스트의 목적은 Tour import가 `places` 테이블에 대량 write를 수행하는 동안 기존 read 기능이 어떤 영향을 받는지 확인하는 것이다.

단위 테스트와 달리 실제 DB transaction, lock, MVCC 동작이 중요하므로 MySQL/InnoDB 기반으로 테스트해야 한다.

## 핵심 질문

- import 중 일반 조회가 실패하는가?
- import 중 조회 latency가 얼마나 증가하는가?
- 같은 row를 update할 때 lock wait이 발생하는가?
- 동시에 import가 두 번 실행되면 어떤 일이 생기는가?
- commit 전 데이터가 read transaction에서 보이는가?

## 추천 방식

학습 목적이라면 Testcontainers MySQL을 추천한다.

장점:

- 테스트 실행 시 MySQL 컨테이너가 자동으로 뜬다.
- 개발자 PC마다 DB 설정을 맞출 필요가 줄어든다.
- CI에서도 같은 방식으로 재현할 수 있다.

## 필요한 의존성 예시

실제 코드를 추가할 때 `build.gradle`에 아래를 넣을 수 있다.

```gradle
testImplementation 'org.testcontainers:junit-jupiter'
testImplementation 'org.testcontainers:mysql'
```

Spring Boot dependency management가 Testcontainers 버전을 관리하지 않는 경우에는 버전을 명시한다.

```gradle
testImplementation 'org.testcontainers:junit-jupiter:1.20.4'
testImplementation 'org.testcontainers:mysql:1.20.4'
```

## 테스트 구조

추천 패키지:

```text
src/test/java/com/heattrip/heat_trip_backend/tour/concurrency/
  TourMysqlConcurrencyTest.java
  TestPlaceFactory.java
  LatencyRecorder.java
```

역할:

| 클래스 | 역할 |
|---|---|
| `TourMysqlConcurrencyTest` | 동시성 테스트 본문 |
| `TestPlaceFactory` | 테스트용 `Place` 데이터 생성 |
| `LatencyRecorder` | latency 수집, avg/p95/p99 계산 |

## 테스트 데이터 설계

외부 Tour API를 실제로 호출하지 않는다. 테스트에서는 `Place` 객체를 직접 만든다.

이유:

- 외부 API 속도와 장애가 테스트 결과를 흔든다.
- 우리는 외부 API 성능이 아니라 DB 동시성을 보고 싶다.
- 같은 데이터셋으로 반복 측정해야 비교가 가능하다.

테스트 데이터 예시:

```java
final class TestPlaceFactory {

    static Place place(long id) {
        return Place.builder()
                .contentid(id)
                .title("테스트 장소 " + id)
                .addr1("서울시 테스트구")
                .mapx(127.0 + (id % 100) * 0.0001)
                .mapy(37.5 + (id % 100) * 0.0001)
                .cat1("A01")
                .cat2("A0101")
                .cat3("A01010100")
                .areacode(1)
                .sigungucode(1)
                .contenttypeid("12")
                .build();
    }

    static List<Place> places(long startId, int count) {
        return LongStream.range(startId, startId + count)
                .mapToObj(TestPlaceFactory::place)
                .toList();
    }
}
```

## Testcontainers 기본 예시

```java
package com.heattrip.heat_trip_backend.tour.concurrency;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

@Testcontainers
@SpringBootTest
class TourMysqlConcurrencyTest {

    @Container
    static MySQLContainer<?> mysql = new MySQLContainer<>("mysql:8.4")
            .withDatabaseName("heattrip_test")
            .withUsername("test")
            .withPassword("test");

    @DynamicPropertySource
    static void mysqlProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", mysql::getJdbcUrl);
        registry.add("spring.datasource.username", mysql::getUsername);
        registry.add("spring.datasource.password", mysql::getPassword);
        registry.add("spring.datasource.driver-class-name", mysql::getDriverClassName);
        registry.add("spring.jpa.hibernate.ddl-auto", () -> "create-drop");
    }

    @Test
    void contextLoadsWithMysql() {
        // MySQL 기반 Spring Context가 뜨는지 확인하는 가장 작은 테스트
    }
}
```

주의:

- 현재 프로젝트는 보안, OAuth, OpenAI, private properties 등 전체 context가 무겁게 뜰 수 있다.
- 처음에는 `@DataJpaTest` + 필요한 repository/service만 import하는 방식이 더 안정적일 수 있다.
- 전체 애플리케이션 context가 실패하면 테스트 profile을 따로 두는 것을 고려한다.

## 동시성 테스트 기본 구조

동시성 테스트는 보통 다음 구조를 가진다.

1. 초기 데이터 insert
2. 여러 read thread 준비
3. write/import thread 준비
4. 동시에 시작하도록 `CountDownLatch` 사용
5. read latency와 실패 수 기록
6. 모든 thread 종료 후 결과 계산

핵심은 read와 write가 정말 동시에 시작되도록 맞추는 것이다.

## JUnit 예시: import 중 read 성공률 측정

아래 코드는 개념 예시다. 실제 프로젝트에서는 `ExploreService`나 repository 메서드에 맞춰 조정한다.

```java
package com.heattrip.heat_trip_backend.tour.concurrency;

import com.heattrip.heat_trip_backend.tour.domain.Place;
import com.heattrip.heat_trip_backend.tour.repository.PlaceRepository;
import com.heattrip.heat_trip_backend.tour.service.PlaceService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.time.Duration;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThat;

@Testcontainers
@SpringBootTest
class TourMysqlConcurrencyTest {

    @Autowired
    PlaceRepository placeRepository;

    @Autowired
    PlaceService placeService;

    @Test
    @DisplayName("places batch 저장 중에도 일반 조회가 실패하지 않는지 측정한다")
    void readsDuringBatchImport() throws Exception {
        placeRepository.saveAll(TestPlaceFactory.places(1, 10_000));
        placeRepository.flush();

        int readerThreads = 8;
        int readsPerThread = 1_000;

        ExecutorService executor = Executors.newFixedThreadPool(readerThreads + 1);
        CountDownLatch ready = new CountDownLatch(readerThreads + 1);
        CountDownLatch start = new CountDownLatch(1);
        CountDownLatch done = new CountDownLatch(readerThreads + 1);

        AtomicInteger success = new AtomicInteger();
        AtomicInteger failure = new AtomicInteger();
        LatencyRecorder latencies = new LatencyRecorder();

        Runnable reader = () -> {
            ready.countDown();
            await(start);
            try {
                for (int i = 0; i < readsPerThread; i++) {
                    long begin = System.nanoTime();
                    try {
                        placeRepository.findById(1L + (i % 10_000));
                        success.incrementAndGet();
                    } catch (Exception e) {
                        failure.incrementAndGet();
                    } finally {
                        latencies.record(System.nanoTime() - begin);
                    }
                }
            } finally {
                done.countDown();
            }
        };

        Runnable writer = () -> {
            ready.countDown();
            await(start);
            try {
                List<Place> updates = TestPlaceFactory.places(1, 10_000).stream()
                        .peek(p -> p.setTitle("갱신된 장소 " + p.getContentid()))
                        .toList();

                placeService.saveInBatches(updates, 200);
            } finally {
                done.countDown();
            }
        };

        for (int i = 0; i < readerThreads; i++) {
            executor.submit(reader);
        }
        executor.submit(writer);

        ready.await(10, TimeUnit.SECONDS);
        start.countDown();

        boolean finished = done.await(60, TimeUnit.SECONDS);
        executor.shutdownNow();

        assertThat(finished).isTrue();
        assertThat(failure.get()).isEqualTo(0);

        System.out.println("success=" + success.get());
        System.out.println("failure=" + failure.get());
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

## LatencyRecorder 예시

```java
final class LatencyRecorder {

    private final List<Long> nanos = new CopyOnWriteArrayList<>();

    void record(long elapsedNanos) {
        nanos.add(elapsedNanos);
    }

    double avgMillis() {
        return nanos.stream()
                .mapToLong(Long::longValue)
                .average()
                .orElse(0.0) / 1_000_000.0;
    }

    double percentileMillis(int percentile) {
        if (nanos.isEmpty()) return 0.0;

        List<Long> sorted = nanos.stream().sorted().toList();
        int index = (int) Math.ceil(percentile / 100.0 * sorted.size()) - 1;
        index = Math.max(0, Math.min(index, sorted.size() - 1));
        return sorted.get(index) / 1_000_000.0;
    }

    double maxMillis() {
        return nanos.stream()
                .mapToLong(Long::longValue)
                .max()
                .orElse(0L) / 1_000_000.0;
    }
}
```

## 중복 import 테스트

현재 구조에는 import 중복 실행 방지가 없다. 이를 보여주고 싶다면 같은 데이터셋을 두 writer가 동시에 저장하게 만든다.

예상 관찰 포인트:

- 최종 row count는 깨지지 않을 수 있다. `contentid`가 PK이기 때문이다.
- 하지만 같은 row update가 겹치면서 lock wait이 증가할 수 있다.
- 마지막 commit이 최종 값을 결정한다.
- import 실행 시간이 증가할 수 있다.

예시:

```java
@Test
@DisplayName("동일한 import가 동시에 실행될 때 소요 시간과 실패 여부를 측정한다")
void duplicatedImport() throws Exception {
    List<Place> importA = TestPlaceFactory.places(1, 20_000);
    List<Place> importB = TestPlaceFactory.places(1, 20_000).stream()
            .peek(p -> p.setTitle("두 번째 import " + p.getContentid()))
            .toList();

    ExecutorService executor = Executors.newFixedThreadPool(2);
    CountDownLatch start = new CountDownLatch(1);

    Future<Long> a = executor.submit(() -> measureMillis(() -> {
        await(start);
        placeService.saveInBatches(importA, 200);
    }));

    Future<Long> b = executor.submit(() -> measureMillis(() -> {
        await(start);
        placeService.saveInBatches(importB, 200);
    }));

    start.countDown();

    long aMs = a.get();
    long bMs = b.get();

    System.out.println("importA ms=" + aMs);
    System.out.println("importB ms=" + bMs);
    System.out.println("rowCount=" + placeRepository.count());

    executor.shutdownNow();
}
```

## 결과 정리 방법

| 시나리오 | writer 수 | reader thread | read 요청 | 실패 | avg | p95 | p99 | max | writer time |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| read only | 0 | 8 | 8,000 | 0 | 12ms | 30ms | 60ms | 110ms | - |
| read + import | 1 | 8 | 8,000 | 0 | 25ms | 100ms | 350ms | 900ms | 20s |
| read + duplicated import | 2 | 8 | 8,000 | 0 | 45ms | 250ms | 1.1s | 3.4s | 42s |

이 표에서 중요한 것은 실패 여부만이 아니다. 실패가 0이어도 p95/p99가 크게 증가하면 사용자 경험에 영향이 있다.
