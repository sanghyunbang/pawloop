# Qodana PR 모드 및 Code Scanning 가이드

## 문서 목적

이 문서는 현재 저장소에서 Qodana를 어떻게 운영할지, 왜 `pr-mode`와 `upload-result` 설정을 조정했는지, 그리고 GitHub Code Scanning을 어떻게 붙일 수 있는지를 정리한 문서다.

이번 문서에 남기는 핵심 목적은 다음과 같다.

- Qodana가 무엇인지 팀 차원에서 공통 이해를 만든다.
- PR 리뷰 관점에서 어떤 설정이 적절한지 이유를 남긴다.
- GitHub Code Scanning 연동 방법과 운영 시 주의점을 남긴다.
- 이번에 바꾼 설정과 그 배경을 나중에도 추적할 수 있게 한다.

## 배경

PR `#7` 리뷰 중 Qodana 봇이 PR 코멘트에 여러 경고를 요약해서 남겼다.

예를 들면 다음과 같은 형태였다.

- `Nullability and data flow problems`
- `AutoCloseable used without 'try'-with-resources`
- `Unused assignment`
- inspection 카테고리별 경고 개수

그런데 이 코멘트만으로는 다음 정보를 알기 어려웠다.

- 정확히 어느 파일이 문제인지
- 어느 줄이 문제인지
- 이번 PR에서 바뀐 코드 때문인지
- 아니면 기존 저장소의 다른 코드 때문인지

원인을 확인해 보니 현재 워크플로우는 다음처럼 설정되어 있었다.

```yml
with:
  pr-mode: false
  use-caches: true
  post-pr-comment: true
  use-annotations: true
  upload-result: false
```

이 설정은 PR 리뷰 관점에서 두 가지 문제를 만들었다.

1. `pr-mode: false`
   - PR 변경 파일만 분석하는 것이 아니라 더 넓은 범위를 보게 되어, 현재 PR과 직접 관련 없는 기존 코드 경고도 같이 섞일 수 있다.

2. `upload-result: false`
   - PR 코멘트에는 요약만 남고, 실제 상세 결과(SARIF, 로그, 기타 결과물)를 artifact로 확인할 수 없다.

즉, 경고는 뜨는데 정확히 어디가 문제인지 추적하기 어려웠고, PR과 무관한 경고가 섞일 가능성도 있었다.

## 이번에 적용한 변경

워크플로우 파일:

- `.github/workflows/qodana_code_quality.yml`

기존:

```yml
with:
  pr-mode: false
  use-caches: true
  post-pr-comment: true
  use-annotations: true
  upload-result: false
```

변경 후:

```yml
with:
  pr-mode: true
  use-caches: true
  post-pr-comment: true
  use-annotations: true
  upload-result: true
```

그리고 GitHub Code Scanning 업로드 단계도 추가했다.

## Qodana가 무엇인가

Qodana는 JetBrains가 제공하는 정적 분석 도구다.

정적 분석이란:

- 애플리케이션을 실제로 실행하지 않고
- 소스코드 자체를 분석해서
- 잠재적인 오류, 품질 문제, 위험 패턴을 찾는 방식이다.

즉, 테스트와는 역할이 다르다.

테스트는 주로 이런 질문에 답한다.

- “실제로 실행해보니 기능이 정상 동작하는가?”

Qodana는 이런 질문에 답한다.

- “이 코드는 실행 전에 봐도 위험하거나 이상한 패턴이 있는가?”

예를 들면 다음과 같은 문제를 찾으려 한다.

- null 가능성 문제
- 값 흐름(data flow) 이상
- 무의미하거나 중복된 분기
- 닫아야 하는 리소스를 안전하게 처리하지 않은 코드
- 사용되지 않는 대입
- 항상 같은 결과를 내는 조건문

따라서 Qodana 경고는 “컴파일 에러”가 아니라 “잠재 문제 후보”라고 보는 것이 맞다.

## 왜 PR 리뷰에서 설정이 중요한가

PR 리뷰의 목적은 현재 변경분을 평가하는 것이다.

그런데 정적 분석기가 PR과 무관한 기존 코드까지 같이 보고 경고를 뿌리면 다음 문제가 생긴다.

- 작성자가 지금 고쳐야 할 문제와 나중에 정리할 기술 부채를 구분하기 어려워진다.
- 리뷰 신호가 흐려진다.
- 툴에 대한 신뢰가 떨어진다.

즉, PR 리뷰에서는 “전체 저장소를 엄격하게 훑는 것”보다 “현재 변경분에 대해 정확한 신호를 주는 것”이 더 중요하다.

그래서 PR 워크플로우에서는 보통 `pr-mode: true`가 더 적절하다.

## 각 옵션 설명

아래는 현재 `with:` 블록에 들어가는 옵션들이 각각 무슨 역할을 하는지에 대한 설명이다.

### `pr-mode: true`

가장 중요한 옵션이다.

무엇을 하는가:

- PR에서 변경된 파일 중심으로 분석한다.

왜 필요한가:

- 현재 PR과 관련된 경고만 보이게 해서 노이즈를 줄인다.
- 기존 저장소의 다른 코드 때문에 생기는 경고를 최대한 배제한다.
- 리뷰어와 작성자가 현재 변경분에 집중할 수 있게 한다.

언제 `false`가 맞는가:

- 야간 전체 품질 점검
- 메인 브랜치 전체 감사
- PR 리뷰가 아니라 저장소 전체 품질 진단이 목적일 때

권장:

- PR 워크플로우에서는 `true`
- 전체 저장소 점검용 별도 워크플로우가 필요하면 그때 `false`

### `use-caches: true`

무엇을 하는가:

- Qodana 실행 시 사용할 캐시를 재사용한다.

왜 필요한가:

- 반복 실행 시 속도가 빨라질 수 있다.
- 불필요한 재분석 비용을 줄인다.

권장:

- 특별한 캐시 문제나 꼬임 이슈가 없다면 `true` 유지

### `post-pr-comment: true`

무엇을 하는가:

- PR 대화창에 Qodana 결과 요약 코멘트를 남긴다.

왜 필요한가:

- PR 화면만 보고 있는 사람도 정적 분석 결과가 있다는 것을 바로 알 수 있다.
- 굳이 Actions 탭까지 들어가지 않아도 된다.

한계:

- 요약만 보여주므로 상세 위치 추적은 부족하다.

권장:

- 팀이 PR 화면에서 바로 결과를 보고 싶다면 `true`

### `use-annotations: true`

무엇을 하는가:

- GitHub Actions 또는 PR 관련 UI에서 annotation 형태로 일부 결과를 노출한다.

왜 필요한가:

- 단순 요약 코멘트보다 조금 더 코드 위치에 가까운 힌트를 줄 수 있다.
- 어떤 파일/영역과 연결되는지 파악하는 데 도움을 준다.

한계:

- 이것만으로는 GitHub Code Scanning 수준의 상세 추적을 제공하지 않는다.

권장:

- `true` 유지

### `upload-result: true`

이번에 같이 바꾼 중요한 옵션이다.

무엇을 하는가:

- Qodana 실행 결과물을 GitHub Actions artifact로 업로드한다.

보통 포함될 수 있는 것:

- SARIF 파일
- 로그 파일
- 기타 분석 결과물

왜 필요한가:

- PR 코멘트만으로 부족할 때 실제 결과 파일을 내려받아 볼 수 있다.
- false positive인지, 어느 파일/라인인지 더 자세히 추적할 수 있다.
- 이후 GitHub Code Scanning 연동 시 SARIF 경로를 확인하는 데도 도움이 된다.

권장:

- Qodana 결과를 실제로 운영하려면 `true`가 훨씬 낫다.

### `push-fixes: 'none'`

무엇을 하는가:

- Qodana가 자동 수정 결과를 브랜치에 푸시하지 않도록 한다.

왜 필요한가:

- 자동 분석기가 임의로 커밋을 만들지 못하게 한다.
- 사람 검토 중심의 PR 흐름을 유지할 수 있다.

권장:

- 기본값으로 `none`이 안전하다.

## Artifact는 누가 받을 수 있는가

이 부분은 보안 관점에서 꼭 알아야 한다.

GitHub 공식 문서 기준으로 workflow artifact는:

- GitHub에 로그인한 사용자 중
- 해당 저장소에 **읽기 권한(read access)** 이 있는 사용자

가 다운로드할 수 있다.

즉, “나만 받을 수 있는가?”에 대한 답은 아니다.

정확히 말하면:

- **저장소를 읽을 수 있는 권한이 있는 사람만** 받을 수 있다.

### private 저장소인 경우

- 읽기 권한이 없는 외부 사용자는 artifact를 받을 수 없다.
- 보통 협업자, 팀원, 권한을 부여받은 사용자만 다운로드 가능하다.

### public 저장소인 경우

- 읽기 권한 범위가 훨씬 넓다.
- 따라서 artifact 안에 민감한 정보가 들어가면 위험하다.

그래서 `upload-result: true`를 사용할 때는 원칙이 있다.

- 로그나 SARIF에 민감한 정보가 들어가지 않게 해야 한다.
- 토큰, 비밀번호, 개인정보, 내부 인프라 식별 정보 같은 것이 남지 않도록 관리해야 한다.

실무적으로는 이렇게 생각하면 된다.

- private repo: artifact 업로드는 비교적 현실적인 선택
- public repo: artifact 내용에 민감 정보가 절대 포함되지 않도록 더 엄격히 관리해야 함

## 왜 이전 코멘트만으로는 부족했는가

이전 Qodana 코멘트는 이런 정보만 보여줬다.

- inspection 이름
- severity
- 문제 개수

하지만 실제로 필요한 것은 보통 이런 정보다.

- 어느 파일인지
- 어느 줄인지
- 어떤 코드가 문제인지
- 이번 PR에서 바뀐 부분인지

그래서 Qodana가 제시한 상세 확인 방법이 다음과 같았다.

- Qodana Cloud 등록
- GitHub Code Scanning 사용
- GitHub Pages에 보고서 호스팅
- `qodana.sarif.json` 직접 확인
- `upload-result: true`로 artifact 업로드

이 중에서 현재 저장소에 가장 실용적인 첫 단계는 다음 두 가지였다.

- `pr-mode: true`
- `upload-result: true`

## GitHub Code Scanning이란 무엇인가

GitHub Code Scanning은 GitHub가 제공하는 정적 분석 결과 표시/관리 기능이다.

정적 분석 도구가 SARIF 형식으로 결과를 업로드하면 GitHub가 그것을 받아서:

- Security 탭
- Code scanning alerts
- PR 연계 UI

같은 곳에서 구조화된 형태로 보여준다.

장점:

- 파일/라인 단위로 추적하기 쉽다.
- PR 요약 코멘트보다 훨씬 실용적이다.
- 장기적으로 어떤 경고가 반복되는지 관리하기 좋다.

즉:

- Qodana는 “문제를 찾는 엔진”
- GitHub Code Scanning은 “그 결과를 GitHub 안에서 잘 보여주는 화면과 저장 구조”

라고 이해하면 된다.

## GitHub Code Scanning은 따로 설치해야 하는가

보통 로컬에 별도 프로그램을 설치할 필요는 없다.

이번 저장소처럼 GitHub Actions 안에서 처리할 때는:

- workflow 설정
- 권한 설정
- SARIF 업로드 step

이 세 가지가 핵심이다.

즉 대부분의 경우:

- GitHub에서 뭔가를 수동으로 다운받아 설치한다기보다
- workflow에 SARIF 업로드 단계를 추가해서 연동한다.

다만 전제가 하나 있다.

GitHub 공식 문서 기준으로 Code Scanning은 다음 조건에서 사용할 수 있다.

- GitHub.com의 public repository
- GitHub Code Security가 활성화된 organization 소유 저장소

또한 private/internal 저장소는 조직 설정과 플랜 상태에 따라 동작 여부가 달라질 수 있다.

즉, 설정만 바꾼다고 무조건 항상 되는 것은 아니고:

- 저장소 유형
- 조직/플랜
- Code Security 활성화 여부

를 함께 봐야 한다.

하지만 public repo이거나, 조직 저장소에서 Code Security가 켜져 있다면 workflow 설정만으로 충분히 붙일 수 있다.

## 왜 GitHub Code Scanning을 추천하는가

현재처럼 PR 코멘트만 쓰면:

- 문제 개수는 보이지만
- 상세 위치는 부족하고
- 장기 추적이 어렵다.

Code Scanning을 붙이면:

- 정확한 위치를 GitHub에서 볼 수 있고
- SARIF 결과를 구조적으로 관리할 수 있고
- PR 리뷰와 장기 품질 관리를 같이 하기 쉬워진다.

그래서 운영 관점에서는 장기적으로 가장 추천되는 방식이다.

## Qodana + Code Scanning 연결 방법

일반적인 흐름은 아래와 같다.

1. Qodana 실행
2. SARIF 결과 생성
3. GitHub에 SARIF 업로드
4. GitHub Code Scanning UI에서 결과 확인

### 필요한 권한

워크플로우 job 권한에 아래가 필요하다.

```yml
permissions:
  actions: read
  contents: write
  pull-requests: write
  checks: write
  security-events: write
```

여기서 중요한 추가 권한은:

- `security-events: write`

이 권한이 없으면 Code Scanning 업로드가 실패할 수 있다.

그리고 private 저장소 관련 사례에서는 다음 권한도 함께 쓰는 것이 일반적이다.

- `actions: read`

현재 저장소에서는 Qodana가 PR 코멘트와 체크도 작성하므로 `contents: write`는 유지하고, Code Scanning 업로드를 위해 `security-events: write`를 추가했다.

## 예시 워크플로우

아래는 개념적으로 권장되는 예시다.

```yml
name: Qodana

on:
  workflow_dispatch:
  pull_request:
  push:
    branches:
      - main

jobs:
  qodana:
    runs-on: ubuntu-latest
    permissions:
      actions: read
      contents: write
      pull-requests: write
      checks: write
      security-events: write

    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Qodana Scan
        uses: JetBrains/qodana-action@v2025.2
        env:
          QODANA_TOKEN: ${{ secrets.QODANA_TOKEN }}
        with:
          pr-mode: true
          use-caches: true
          post-pr-comment: true
          use-annotations: true
          upload-result: true

      - name: Upload SARIF to GitHub Code Scanning
        uses: github/codeql-action/upload-sarif@v4
        with:
          sarif_file: ${{ runner.temp }}/qodana/results/qodana.sarif.json
          category: qodana
```

## 중요한 주의사항

위 예시는 개념적으로는 맞지만, 실제 `sarif_file` 경로는 Qodana 액션 버전이나 실행 환경에 따라 달라질 수 있다.

즉, Code Scanning까지 안정적으로 붙이기 전에 먼저 해야 할 일은 다음이다.

1. `upload-result: true`로 artifact를 남긴다.
2. 실제 artifact 안에서 SARIF 경로를 확인한다.
3. 그 경로를 기준으로 `upload-sarif` step을 검증한다.

다만 Qodana 공식 문서에서는 기본 결과 디렉터리를 다음처럼 설명한다.

- `${{ runner.temp }}/qodana/results`

그리고 예시 SARIF 파일 경로도 다음을 사용한다.

- `${{ runner.temp }}/qodana/results/qodana.sarif.json`

그래서 이번 저장소에서는 이 공식 기본 경로를 기준으로 실제 step을 추가했다.

## 이번 저장소에 실제 반영한 Code Scanning 설정

현재 워크플로우에는 아래 step을 추가했다.

```yml
- name: Upload SARIF to GitHub Code Scanning
  uses: github/codeql-action/upload-sarif@v4
  with:
    sarif_file: ${{ runner.temp }}/qodana/results/qodana.sarif.json
    category: qodana
```

`category: qodana`를 지정한 이유는 다음과 같다.

- 이 결과가 Qodana에서 온 SARIF라는 것을 GitHub 측에서 구분하기 쉽게 하기 위함
- 나중에 다른 도구의 SARIF를 추가로 업로드하더라도 출처 구분이 쉬워짐

## 현재 저장소에 대한 추천 순서

### 1단계

먼저 지금처럼 설정한다.

```yml
with:
  pr-mode: true
  use-caches: true
  post-pr-comment: true
  use-annotations: true
  upload-result: true
```

왜:

- PR 관련 경고만 보게 해서 노이즈를 줄인다.
- artifact를 통해 상세 결과를 확인할 수 있다.

### 2단계

몇 번의 PR에서 artifact를 실제로 확인한다.

확인할 것:

- 실제 SARIF 파일 경로
- 로그 파일 위치
- 결과물이 충분히 상세한지

### 3단계

그 다음 GitHub Code Scanning 업로드 결과를 확인한다.

확인할 것:

- Security 탭/Code Scanning alert에 결과가 정상 반영되는지
- PR UI에서 위치 추적이 개선되는지

## PR과 무관한 경고가 뜨는 경우

질문한 내용처럼 현재 PR과 무관한 다른 부분에서 경고가 뜰 수 있다.

특히 `pr-mode: false`에서는 그 가능성이 높다.

그런 경우에는:

- 그것이 현재 PR 작성자의 실수라고 단정하면 안 된다.
- 저장소 전체 품질 부채일 가능성을 봐야 한다.
- PR 차단 기준으로 쓰기보다 후속 정리 대상으로 관리하는 편이 맞다.

이 때문에 PR 워크플로우에서는 `pr-mode: true`가 훨씬 적절하다.

## 이번 결정의 요약

이번 저장소에서는 다음 기준이 가장 합리적이다.

기본 운영:

```yml
with:
  pr-mode: true
  use-caches: true
  post-pr-comment: true
  use-annotations: true
  upload-result: true
```

추가 적용:

- `security-events: write` 권한 추가
- `github/codeql-action/upload-sarif@v4` step 추가
- Qodana SARIF를 GitHub Code Scanning으로 업로드

## 관련 파일

- `.github/workflows/qodana_code_quality.yml`
- `qodana.yaml`

## 최종 권장 사항

현재 저장소 기준으로 가장 추천하는 방향은 다음이다.

1. PR 리뷰에서는 `pr-mode: true`를 사용한다.
2. 상세 결과 추적을 위해 `upload-result: true`를 사용한다.
3. GitHub Code Scanning까지 붙여서 파일/라인 단위로 결과를 보게 한다.

즉, 지금은 “Qodana 요약 코멘트만 보는 단계”에서 벗어나:

- PR 관련성은 높이고
- 상세 결과 접근성은 확보하고
- GitHub 네이티브 분석 화면으로 연결하는 단계라고 보면 된다.
