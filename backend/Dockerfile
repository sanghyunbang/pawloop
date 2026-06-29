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
ENTRYPOINT ["sh","-c","java $JAVA_OPTS -jar app.jar --server.address=${SERVER_ADDRESS:-0.0.0.0} --server.port=${SERVER_PORT:-8080}"]
