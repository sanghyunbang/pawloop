package com.heattrip.heat_trip_backend.S3;

import com.amazonaws.auth.AWSStaticCredentialsProvider;
import com.amazonaws.auth.BasicAWSCredentials;
import com.amazonaws.services.s3.AmazonS3;
import com.amazonaws.services.s3.AmazonS3ClientBuilder;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.PropertySource;

// S3에 접근 할 수 있도록 클라이언트 생성하는 부분!
// @PropertySource("classpath:application_AWS.properties")
@Configuration
public class AmazonS3Config {
    // 프로퍼티에 적어놓은 정보들 담는 부분분
    @Value("${cloud.aws.credentials.access-key}")
    private String accessKey;

    @Value("${cloud.aws.credentials.secret-key}")
    private String secretKey;

    @Value("${cloud.aws.region.static}")
    private String region;
    
    // 이 객체를 만들어서 Spring 컨테이너에 등록하고, 이걸로 S3 접근함!
    // 여기서 AmazonS3는 인터페이스고 리턴되는 객체는 AmazonS3Client
    @Bean
    public AmazonS3 amazonS3() {
        // AWS 자격 증명 관련한 객체 생성하기
        BasicAWSCredentials creds = new BasicAWSCredentials(accessKey, secretKey);
        // S3 클라이언트 생성 하고 Bean 등록하기  
        return AmazonS3ClientBuilder.standard()
                .withRegion(region)
                .withCredentials(new AWSStaticCredentialsProvider(creds))
                .build();
    }
}