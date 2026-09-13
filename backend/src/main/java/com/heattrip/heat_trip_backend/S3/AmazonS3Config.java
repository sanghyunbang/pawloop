package com.heattrip.heat_trip_backend.S3;

import com.amazonaws.ClientConfiguration;
import com.amazonaws.auth.AWSStaticCredentialsProvider;
import com.amazonaws.auth.BasicAWSCredentials;
import com.amazonaws.services.s3.AmazonS3;
import com.amazonaws.services.s3.AmazonS3ClientBuilder;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * S3 클라이언트 빈.
 *
 * <h2>밖으로 나가는 호출에 타임아웃과 상한을 건다 (#86 원칙 3 · #429)</h2>
 * <p>정하지 않는 것은 "무한" 을 고른 것이다. 여기서 정한 넷:
 * <ol>
 *   <li><b>타임아웃</b> — 연결 {@value #CONNECT_TIMEOUT_MS}ms, 소켓 {@value #SOCKET_TIMEOUT_MS}ms.
 *       소켓 타임아웃은 "다음 바이트를 기다리는 시간" 이라 10MB 사진을 올리는 동안 쌓이지 않는다.</li>
 *   <li><b>재시도</b> — SDK 기본 정책에 최대 {@value #MAX_ERROR_RETRY}회. 5xx·연결 오류에만 재시도하고
 *       4xx 는 하지 않는다(SDK 의 {@code PredefinedRetryPolicies.DEFAULT} 규칙).</li>
 *   <li><b>최악 소요</b> — 연결 5s + 소켓 30s 가 3번이면 105초다. 앞단 nginx 의 120초보다 작다.</li>
 *   <li><b>실패했을 때</b> — 예외로 즉시 실패한다. 업로드 경로는 500 이고 트랜잭션이 되돌아가
 *       행이 안 남는다. 삭제 경로도 예외라 행이 남고 다음 청소가 다시 시도한다.</li>
 * </ol>
 *
 * <p>presigned URL 만들기는 네트워크를 안 탄다 — 자격 증명으로 서명만 한다. 그래서 dev 의
 * 자리표시 자격 증명으로도 URL 은 만들어지고, 진짜로 실패하는 것은 그 URL 로 S3 에 갈 때다.
 *
 * <p>정적 액세스 키를 쓰는 이유는 #86 §10 에 있다 — 운영이 Mac mini 라 인스턴스 롤이 없다.
 */
@Configuration
public class AmazonS3Config {

    static final int CONNECT_TIMEOUT_MS = 5_000;
    static final int SOCKET_TIMEOUT_MS = 30_000;
    static final int MAX_ERROR_RETRY = 2;

    @Value("${cloud.aws.credentials.access-key}")
    private String accessKey;

    @Value("${cloud.aws.credentials.secret-key}")
    private String secretKey;

    @Value("${cloud.aws.region.static}")
    private String region;

    @Bean
    public AmazonS3 amazonS3() {
        BasicAWSCredentials creds = new BasicAWSCredentials(accessKey, secretKey);
        ClientConfiguration clientConfiguration = new ClientConfiguration()
                .withConnectionTimeout(CONNECT_TIMEOUT_MS)
                .withSocketTimeout(SOCKET_TIMEOUT_MS)
                .withMaxErrorRetry(MAX_ERROR_RETRY);
        return AmazonS3ClientBuilder.standard()
                .withRegion(region)
                .withCredentials(new AWSStaticCredentialsProvider(creds))
                .withClientConfiguration(clientConfiguration)
                .build();
    }
}
