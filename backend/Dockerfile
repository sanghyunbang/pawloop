# Build stage
FROM gradle:8.10.2-jdk21 AS build
WORKDIR /workspace
COPY . .
RUN ./gradlew clean bootJar --no-daemon

# Run stage
FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /workspace/build/libs/*.jar app.jar
ENV JAVA_OPTS="-Xms256m -Xmx512m"
EXPOSE 8080
# 프로필/스위치 없이 private 파일이 모든 값을 결정
# `exec` 가 있어야 한다 — 이슈 #787.
#
# 이 줄은 exec 형식(JSON 배열)이지만 그 안에서 `sh -c` 를 거치므로, 1번 프로세스는
# java 가 아니라 **셸**이 된다. 그러면 `docker stop` 의 SIGTERM 이 셸에게 가고 java 에는
# 안 닿는다. dash 는 단일 명령이어도 자리를 비켜 주지 않는다(bash 와 다르다 — 실제로
# 재 봤다). 그래서 java 는 신호를 못 받고 10초를 멀쩡히 일하다가 SIGKILL 로 즉사한다.
#
# 2026-10-21 측정: 재기동 명령 뒤 **10.2초 동안 HTTP 200** 을 주다가 뚝 끊겼다. 세 번
# 다 같았다. 그 순간 처리 중이던 요청·DB 커넥션·버퍼가 통째로 날아간다.
#
# `exec` 를 붙이면 셸이 자기를 java 로 바꿔치우고 사라져서 java 가 1번이 된다. 변수
# 확장과 기본값은 그대로 둬야 하므로 `sh -c` 자체는 남긴다.
#
# **끊긴 시간은 이걸로 안 줄어든다.** 끄는 쪽이 빨라지면 새 컨테이너도 그만큼 먼저
# 시작하므로 끊김은 그대로다. 줄어드는 것은 배포 전체 시간이고, 고쳐지는 것은 안전이다.
ENTRYPOINT ["sh","-c","exec java $JAVA_OPTS -jar app.jar --server.address=${SERVER_ADDRESS:-0.0.0.0} --server.port=${SERVER_PORT:-8080}"]
