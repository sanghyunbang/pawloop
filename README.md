# Heat Trip 🐳 v2.0.0

> 감정으로 떠나는 여행 — *이런 기분일 땐, 이런 곳.*
> 기분을 기록하고, 그 감정에 맞는 장소를 발견하고, 다녀온 감정을 지도에 남기는 **감정 여행 앱**.

**v2.0.0 — 완전히 새로 쓴 버전.** 컨셉·화면 전면 개편, Flutter + 백엔드를 한 repo로 통합, Python 추천 서버 → **Spring AI**로 단순화.

## 구조 (모노레포)
```
heattrip/
├── app/              Flutter 모바일 앱
├── backend/          Java 21 · Spring Boot 3.5 · MySQL 8 (+ Spring AI 전환 예정)
├── design_refactor/  화면/컨셉 개편 디자인 핸드오프 (Claude Design)
└── README.md
```

## 스택
- **app** — Flutter
- **backend** — Java 21 · Spring Boot 3.5 · MySQL 8 · Docker
- **AI** — Spring AI (LLM 프롬프트) — 기존 Python 추천 서버 대체 *(전환 예정)*
- **관측성/부하** — Prometheus · Grafana · k6

## 상태
🚧 **v2.0.0 개발 중.** 백엔드 마무리 순서: **DB 튜닝 → 테스트 → Spring Batch → Auth 보완.**

---
*CetaceaLab · 자매 프로젝트: Baleen(불안 동반자)*
