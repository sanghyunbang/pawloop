package com.heattrip.heat_trip_backend.walk.ai;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.openai.OpenAiChatOptions;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.stereotype.Component;

import java.util.Optional;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;

/**
 * Spring AI 의 {@link ChatClient} 로 OpenAI 를 부른다 — 이슈 #486.
 *
 * <p>{@code ChatClient.Builder} 빈은 {@code spring.ai.model.chat=openai} 와 {@code OPENAI_API_KEY} 가
 * 있을 때만 생긴다(기본은 {@code none}). 없으면 {@link #available()} 이 false 이고 기능은 꺼진 채
 * 나간다 — 관측 모듈의 {@code SpringAiErrorSummarizer} 와 같은 방식이다.
 *
 * <p>응답은 {@link WeeklyInsightProperties#timeoutSeconds()} 안에 와야 한다. 통계 화면이 이 호출을
 * 기다리므로(캐시가 없는 주에 한 번) 무한정 붙잡히면 안 된다.
 */
@Component
@EnableConfigurationProperties(WeeklyInsightProperties.class)
public class SpringAiWeeklyInsightModel implements WeeklyInsightModel {

    private static final Logger log = LoggerFactory.getLogger(SpringAiWeeklyInsightModel.class);

    /** 두 문장 + 제안 한 줄이면 넉넉하다 — 추론 모델은 생각 토큰도 여기서 쓴다. */
    static final int MAX_COMPLETION_TOKENS = 600;

    private final ObjectProvider<ChatClient.Builder> chatClientBuilders;
    private final WeeklyInsightProperties props;
    private final String modelName;
    private final String chatModelSetting;

    public SpringAiWeeklyInsightModel(ObjectProvider<ChatClient.Builder> chatClientBuilders,
                                      WeeklyInsightProperties props,
                                      @Value("${spring.ai.openai.chat.options.model:gpt-4.1-mini}") String modelName,
                                      @Value("${spring.ai.model.chat:none}") String chatModelSetting) {
        this.chatClientBuilders = chatClientBuilders;
        this.props = props;
        this.modelName = modelName;
        this.chatModelSetting = chatModelSetting;
    }

    /**
     * 켜졌는가 — 속성 스위치 · {@code spring.ai.model.chat=openai} · 빌더 빈.
     *
     * <p>{@code spring.ai.model.chat=none} 이어도 {@code ChatClient.Builder} 의 빈 <b>정의</b>는 남아 있고,
     * 만들려는 순간 {@code ChatModel} 이 없어 {@code UnsatisfiedDependencyException} 을 던진다.
     * {@code getIfAvailable()} 은 그 예외를 "없음" 으로 바꿔 주지 않으므로 속성으로 먼저 거르고,
     * 그래도 던지면 없는 것으로 본다 — 통계 화면이 500 이 되는 자리였다.
     */
    @Override
    public boolean available() {
        return props.enabled() && "openai".equalsIgnoreCase(chatModelSetting) && builder() != null;
    }

    private ChatClient.Builder builder() {
        try {
            return chatClientBuilders.getIfAvailable();
        } catch (RuntimeException e) {
            log.warn("[AI 주간 요약] ChatClient.Builder 를 만들 수 없다 — 기능을 끈 채 간다: {}", e.toString());
            return null;
        }
    }

    @Override
    public String name() {
        return modelName;
    }

    @Override
    public Optional<String> complete(String system, String user) {
        ChatClient.Builder builder = builder();
        if (builder == null) {
            return Optional.empty();
        }
        ChatClient client = builder.build();
        // GPT-5 계열은 temperature 를 기본값(1) 외에 받지 않고 max_tokens 대신 max_completion_tokens 를 쓴다.
        // Spring AI 의 기본 옵션(temperature 0.7)이 그대로 가면 400 이다 — 여기서 명시한다. 4.1 계열도 같은 값을 받는다.
        OpenAiChatOptions options = OpenAiChatOptions.builder()
                .temperature(1.0)
                .maxCompletionTokens(MAX_COMPLETION_TOKENS)
                .build();
        CompletableFuture<String> call = CompletableFuture.supplyAsync(() ->
                client.prompt().system(system).user(user).options(options).call().content());
        try {
            String content = call.get(props.timeoutSeconds(), TimeUnit.SECONDS);
            if (content == null || content.isBlank()) {
                return Optional.empty();
            }
            return Optional.of(content.trim());
        } catch (Exception e) {
            call.cancel(true);
            // 키 문제 · 시간 초과 · 망 — 어느 쪽이든 문장 없이 나간다. 1단계 문장이 그 자리다.
            log.warn("[AI 주간 요약] 모델 호출 실패: {}", e.toString());
            return Optional.empty();
        }
    }
}
