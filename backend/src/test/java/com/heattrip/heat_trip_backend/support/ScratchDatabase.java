package com.heattrip.heat_trip_backend.support;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.stream.Collectors;

import org.testcontainers.containers.MySQLContainer;

/**
 * 공유 컨테이너 안에 만드는 <b>일회용 데이터베이스</b> 하나. {@link #close()} 가 통째로 지운다.
 *
 * <h2>왜 필요한가</h2>
 * <p>{@code mysql/init/01_schema.sql} 은 <b>빈 DB 를 세우는 파일</b>이다. 그 파일이 실제로
 * 무엇을 만드는지 보려면 표가 아직 하나도 없는 DB 가 있어야 하는데, 스프링 테스트가 붙어
 * 있는 DB 는 Hibernate 가 엔티티로 이미 만들어 둔 상태라 쓸 수 없다.
 *
 * <p><b>스프링을 띄우지 않는다.</b> 공유 컨테이너에 root 로 붙어 데이터베이스를 하나 만들
 * 뿐이라 컨텍스트를 늘리지 않는다(#21). {@code ChatRoomSchemaMigrationExecutionTest} 가
 * {@code post-start/06} 에 대해 같은 방식을 쓴다.
 *
 * <p>원래 {@code SchemaDdlDriftTest} 안의 private 중첩 클래스였다. {@code ChatBoundaryArchitectureTest}
 * 가 정본 스키마를 <b>실제로 적용해서</b> 제약을 확인하게 되면서 같은 지그가 두 곳에
 * 필요해졌고, 사본을 만드는 대신 여기로 뺐다.
 */
public final class ScratchDatabase implements AutoCloseable {

    /** 운영 스키마 정본 — backend 루트 기준 상대 경로. */
    public static final String COMMITTED_SCHEMA = "mysql/init/01_schema.sql";

    private static int counter = 0;

    private final String name;
    private final Connection connection;

    /** 커밋된 운영 스키마만 적용한 일회용 데이터베이스. */
    public static ScratchDatabase withCommittedSchema() throws Exception {
        ScratchDatabase db = new ScratchDatabase();
        String sql = Files.readString(
                TestProjectPaths.requireFile(COMMITTED_SCHEMA), StandardCharsets.UTF_8);
        try (Statement st = db.connection.createStatement()) {
            for (String statement : executableStatements(sql)) {
                st.execute(statement);
            }
        }
        return db;
    }

    private ScratchDatabase() throws SQLException {
        MySQLContainer<?> mysql = MySqlTestContainer.instance();
        synchronized (ScratchDatabase.class) {
            name = "schema_check_" + (++counter);
        }
        // 앱 계정에는 CREATE DATABASE 권한이 없다 — root 로 붙는다(#56 에서 실측).
        String serverUrl = mysql.getJdbcUrl().replaceAll("/[^/?]+(\\?|$)", "/$1");
        try (Connection admin = DriverManager.getConnection(
                serverUrl, "root", mysql.getPassword());
             Statement st = admin.createStatement()) {
            st.execute("DROP DATABASE IF EXISTS " + name);
            st.execute("CREATE DATABASE " + name + " CHARACTER SET utf8mb4");
        }
        connection = DriverManager.getConnection(
                serverUrl.replaceFirst("/(\\?|$)", "/" + name + "$1"),
                "root", mysql.getPassword());
    }

    /**
     * 이 데이터베이스로 붙은 커넥션.
     *
     * <p><b>닫지 마라.</b> 소유권은 이 객체에 있다 — 밖에서 닫으면 정리할 때
     * {@code ConnectionIsClosedException} 이 난다(실측).
     */
    public Connection connection() {
        return connection;
    }

    /** 첫 컬럼만 문자열로 뽑는 조회. {@code information_schema} 를 읽는 데 쓴다. */
    public List<String> queryStrings(String sql) throws SQLException {
        List<String> out = new ArrayList<>();
        try (Statement st = connection.createStatement();
             ResultSet rs = st.executeQuery(sql)) {
            while (rs.next()) {
                out.add(rs.getString(1));
            }
        }
        return out;
    }

    @Override
    public void close() throws SQLException {
        try (Statement st = connection.createStatement()) {
            st.execute("DROP DATABASE IF EXISTS " + name);
        } finally {
            connection.close();
        }
    }

    /**
     * <b>실행용</b> 분리기. 주석만 걷고 대소문자는 건드리지 않는다.
     *
     * <p>비교용 분리기처럼 소문자화하면 {@code ENUM('IN_PROGRESS','NEW','RESOLVED')} 가
     * 소문자로 바뀌어 <b>스키마 자체가 달라진다</b>(실측으로 확인 — 컬럼 정의 비교가 전부
     * 빨간불이었다).
     */
    private static List<String> executableStatements(String ddl) {
        String withoutComments = Arrays.stream(ddl.split("\\R"))
                .filter(line -> !line.strip().startsWith("--"))
                .collect(Collectors.joining("\n"));
        return Arrays.stream(withoutComments.split(";"))
                .map(String::strip)
                .filter(s -> !s.isEmpty())
                .toList();
    }
}
