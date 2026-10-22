# Push (푸시 알림) — 백엔드 (서버 쪽, #83)

> 계약: [`openapi.yaml`](../../04-api/openapi.yaml) `Push` 태그(`/api/push/tokens`, `/api/push/settings`)와 `Chat` 의 `PUT /api/chat/rooms/{roomId}/mute` · 데이터: [erd.md](../../03-database/erd.md) `device_token` · `push_preference`, [schema.md](../../03-database/schema.md) §29 · §30 · §13(`muted_at`)
> 이슈: [#83](https://github.com/sanghyunbang/pawloop/issues/83) · 원칙: [#86](https://github.com/sanghyunbang/pawloop/issues/86) §3·§4·§5 · 로드맵 M2.8

**2026-09-06 에 서버 쪽을 다 짰다.** 앱 쪽(`firebase_core` · `firebase_messaging` · 알림 설정 화면)은 운영자가 Firebase 프로젝트에서 받는 `google-services.json` · `GoogleService-Info.plist` 가 와야 붙는다. 그전까지 서버는 **키 없이** 뜬다 — 토큰 등록·설정·음소거는 저장되고 발송만 조용히 건너뛴다.

---

## 1. 개요

| 항목 | 내용 |
| --- | --- |
| 책임 | 기기 토큰 원장(등록 upsert · 폐기 · 탈퇴 삭제), 사용자별 전체 끄기, 채팅 메시지의 **커밋 뒤 비동기** 발송 |
| 관련 테이블 | `device_token`(주) · `push_preference` · `chat_room_member.muted_at`(방별 음소거 — `chat` 이 소유) |
| 인증 | 전부 인증 필요. 주체는 토큰의 주인 — 경로에 사용자 id 가 없다 |
| 한도 | `PUT` 셋은 `group-write` 버킷(`PUT /api/consents` 와 같은 판단). `GET /api/push/settings` 는 버킷 없음 |
| 패키지 | `com.heattrip.heat_trip_backend.push.{controller,service,repository,entity,dto,fcm,config,metrics}` + `config/AsyncConfig` |
| 의존 | `push → chat`(`ChatMessagePosted` · `notifiableMembers`) · `push → user`(`UserSessionsRevoked` · `@CurrentUser` · `User`) · `push → schedule`(`ScheduleAssigned`, #735). **`chat` · `user` · `schedule` 은 `push` 를 모른다** |

---

## 2. 표면

| HTTP · 경로 | 시그니처 | 응답 | 비고 |
| --- | --- | --- | --- |
| `PUT /api/push/tokens` | `register(@CurrentUser User me, @Valid PushTokenRequest{token, platform})` | `204` | upsert. 같은 기기에서 다른 계정이 등록하면 **주인이 바뀐다** |
| `GET /api/push/settings` | `settings(@CurrentUser User me)` | `PushSettings{enabled}` | 행이 없으면 `true` |
| `PUT /api/push/settings` | `update(@CurrentUser User me, @Valid PushSettingsRequest{enabled})` | `PushSettings` | `{}` 는 400 — 빠진 필드를 false 로 읽으면 "끄기" 가 된다 |
| `PUT /api/chat/rooms/{roomId}/mute` | `ChatRoomController.mute(@CurrentUser User, roomId, ChatMuteRequest{muted})` | `RoomMute{roomId, muted}` | 살아 있는 멤버만(아니면 403). 방 목록의 `ChatRoom.muted` 에 실린다 |

---

## 3. 발송 경로 — 커밋 뒤, 다른 스레드

```
ChatRoomService.postMessage (@Transactional)
  └─ saveAndFlush(message) → events.publishEvent(ChatMessagePosted)   ← 트랜잭션 안
                                        │
                        커밋 ───────────┘
                                        ▼
PushDispatcher.onMessagePosted  @TransactionalEventListener(AFTER_COMMIT) @Async("pushExecutor")
  1. chat.notifiableMembers(roomId, sender)   — 살아 있는 멤버 − 보낸 사람 − 음소거한 사람
  2. preferences.onlyEnabled(...)             — 전체 끈 사람 제외
  3. deviceTokens.activeTokensOf(...)         — revoked_at IS NULL
  4. fcm.send(tokens, PushMessage.forChat)    — 500개씩 · notification + data
  5. 죽은 토큰(UNREGISTERED · INVALID_ARGUMENT · SENDER_ID_MISMATCH) → revoked_at
```

- **왜 커밋 뒤인가** — 저장 트랜잭션 안에서 외부 HTTP 를 부르면 FCM 지연이 곧 채팅 지연이고, 방 행 잠금을 쥔 채 기다린다. 커밋 전에 보내면 롤백된 메시지의 알림이 나간다. `PushDispatchIntegrationTest.sendsAfterCommit` 이 "발송 시점에 트랜잭션이 없고 행이 다른 연결에서 보인다" 를 잰다 — `AFTER_COMMIT` 을 `@EventListener` 로 되돌리면 빨간불이다(완료 조건 3).
- **왜 다른 스레드인가** — 같은 테스트의 `theResponseDoesNotWaitForDispatch` 가 발송을 문 앞에서 막아 둔 채 전송 응답이 돌아오는지 잰다. `@Async` 를 떼면 같이 기다린다.
- **실행기** — `config/AsyncConfig.pushExecutor`: 스레드 2~4, 큐 1,000, **넘치면 버리고 경고**. `CallerRunsPolicy` 를 쓰지 않는 이유는 그 순간 요청 스레드가 FCM 을 부르게 되기 때문이다. 큐는 인메모리 상태다 — 인스턴스가 둘이면 각자 든다(#86 §2).
- **실패는 삼킨다** — 실행기 스레드에서 던지면 아무도 못 본다. `PushMetrics` 가 세고(`push.dispatch{outcome}` · `push.tokens{result}`) 경고 로그를 남긴다. 알림은 최선 노력이다 — 메시지는 이미 저장됐고 다음 폴링이 가져온다.

---

## 4. 키 — 비어 있어도 뜬다

| 프로퍼티 | 환경변수 | 뜻 |
| --- | --- | --- |
| `app.push.firebase.credentials-file` | `APP_PUSH_FIREBASE_CREDENTIALS_FILE` | 서비스 계정 JSON 파일 경로 |
| `app.push.firebase.credentials-json` | `APP_PUSH_FIREBASE_CREDENTIALS_JSON` | 같은 JSON 을 base64 한 줄로(CI 시크릿용) |
| `app.push.firebase.connect-timeout-ms` / `read-timeout-ms` | — | 5,000 / 10,000 — 밖으로 나가는 호출의 상한(#86 §4) |
| `app.push.max-active-tokens-per-user` | — | 10 — 넘치면 가장 오래 안 보인 토큰부터 폐기 |

`PushConfig.fcmClient` 가 고른다 — 둘 다 비면 `NoopFcmClient`, 있으면 `FirebaseFcmClient(FirebaseFcmTransport)`. **키를 못 읽어도 부팅을 막지 않는다** — 경고 한 줄과 꺼진 발송(`PushConfigTest`). 발급 절차는 `backend/.env.example` 의 Firebase 블록에 있다. **서비스 계정 JSON 은 `.env`·시크릿에만 둔다.**

---

## 5. 데이터

| 표 | 무엇 | 특이 |
| --- | --- | --- |
| `device_token` | 기기 토큰 원장 | `UNIQUE(token)` · `user_id` 는 값만(FK 없음) · 지우지 않고 `revoked_at`(로그아웃 · FCM 이 죽었다 함) · **탈퇴만 삭제** |
| `push_preference` | 전체 끄기 | `user_id` PK · 행이 없으면 켜진 것 · 탈퇴 때 삭제 |
| `chat_room_member.muted_at` | 방별 음소거 | 멤버십의 속성이라 `chat` 이 든다. `ChatRoomService.setMuted` |

시각은 전부 UTC — `PushTime.nowUtc()`(`StoredTimestampsAreUtcTest` · `TimeWritersAreUtcTest`). 마이그레이션은 [`25_push.sql`](../../../backend/mysql/post-start/25_push.sql)(`PushSchemaMigrationExecutionTest` 가 진짜 MySQL 에 돌려 본다).

---

## 6. 로그아웃 · 탈퇴

`UserService.logout`·`deleteMe` 가 트랜잭션 안에서 `UserSessionsRevoked(userId, accountDeleted)` 를 발행하고, `PushDispatcher.onSessionsRevoked` 가 커밋 뒤에 받는다 — 로그아웃은 전 기기 토큰 폐기(계약의 `POST /auth/logout` 이 전 기기라서 같다), 탈퇴는 토큰 행과 설정 행 삭제. `user` 는 `push` 를 모른다(`allowedDependencies = {}`).

---

## 7. 남은 것 (앱 · 사람 손)

- ✅ Android 는 앱까지 이어졌다(2026-09-21). Firebase 프로젝트 `pawloop-b3393` 에 `app.pawloop` 이 등록돼 있고, `app/lib/v2/data/firebase_push.dart` 가 Firebase 를 아는 유일한 파일이다 — 로그인이 확정되면 `PUT /api/push/tokens`, 앞에 있을 때는 `flutter_local_notifications` 로 띄우고, 누르면 기기 알림과 같은 길(`notification_route.dart`)로 간다(`docs/02-architecture/frontend-structure.md` §2.3). `google-services.json` 은 저장소 밖(gitignore) — 없으면 gradle 이 플러그인을 안 얹고 앱은 푸시 없이 뜬다.
- ✅ `privacy_ko.md` v1.10 에 기기 알림 토큰 항목(완료 조건 4).
- iOS: `GoogleService-Info.plist` · APNs `.p8`(Apple Developer 계정 — #301 과 같은 계정) — 맥에서.
- 앱의 알림 설정 화면(전체 끄기 `PUT /api/push/settings` · 방별 음소거 — 방 목록의 `muted`)은 아직 없다.
- 운영 서버의 `APP_PUSH_FIREBASE_CREDENTIALS_FILE`(서비스 계정 JSON, 저장소 밖) — 맥에서 올린다. 서비스 계정 키는 프로젝트 id 도 들고 있어 부팅 로그가 그 이름을 찍는다.
- 완료 조건 1(실기기 도착)은 사람이 본다 — Android 실기기 + iOS 실기기 + APNs 키. 에뮬레이터 도착은 2026-09-21 실측(#83 댓글의 캡처).

---

## 배정 푸시 — 일정 (#735)

```
ScheduleService.create / update (@Transactional)
  └─ 담당이 남이 됐으면 events.publishEvent(ScheduleAssigned)   ← 트랜잭션 안 (담당이 나면 · 안 바뀌었으면 발행 안 함)
                                        │
                        커밋 ───────────┘
                                        ▼
PushDispatcher.onScheduleAssigned  @TransactionalEventListener(AFTER_COMMIT) @Async("pushExecutor")
  1. preferences.onlyEnabled([담당자])       — 전체 끈 사람 제외 (방별 음소거는 없다)
  2. deviceTokens.activeTokensOf(...)       — 살아 있는 토큰
  3. fcm.send(PushMessage.forScheduleAssigned) — "엄마님이 일정을 맡겼어요 / 내일 10:30 · 뭉치 병원", data{kind: schedule.assigned, scheduleId, onDate}
```

사건은 값만 든다(아이 이름까지 트랜잭션 안에서 읽어 둔다 — 듣는 쪽은 다른 스레드라 지연 로딩이 터진다). 실측은 `ScheduleAssignedPushIntegrationTest`(담당자에게 한 번 · 커밋 뒤 · 나 자신은 조용 · 바뀔 때만 · 끈 사람은 건너뜀) 와 `PushMessageTest`(문구). **앱에 FCM 이 붙는 #83 뒤에야 기기에 도착한다** — 지금은 서버가 보내는 자리까지다.
