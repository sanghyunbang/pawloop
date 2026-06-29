# SQL Query Optimization For Explore Search

## 목적

이 폴더는 `GET /api/explore/places/search` 검색 경로의 SQL 최적화 작업을 정리한다.
대상은 특히 `q=카페` 같은 텍스트 검색 케이스이며, 기존 `LIKE '%keyword%' + EXISTS` 구조를
`FULLTEXT + ngram` 기반 구조로 전환한 배경, 구현, 운영 절차를 기록한다.

## 문서 목록

1. [1_problem_and_baseline.md](./1_problem_and_baseline.md)
   기존 문제 상황, 증상, 초기 관찰을 정리한다.

2. [2_root_cause_analysis.md](./2_root_cause_analysis.md)
   기존 SQL이 왜 느렸는지 실행계획 기준으로 해석한다.

3. [3_solution_design.md](./3_solution_design.md)
   왜 `search_text + FULLTEXT + ngram` 구조를 선택했는지 설명한다.

4. [4_mysql_migration_and_runbook.md](./4_mysql_migration_and_runbook.md)
   MySQL에서 실제로 수행한 작업, 명령, 오류 대응을 정리한다.

5. [5_code_changes.md](./5_code_changes.md)
   백엔드 코드에서 무엇을 어떻게 바꿨는지 파일 단위로 정리한다.

6. [6_before_after_execution_plans.md](./6_before_after_execution_plans.md)
   변경 전/후 `EXPLAIN ANALYZE`와 의미를 비교한다.

7. [7_validation_and_regression.md](./7_validation_and_regression.md)
   테스트, 확인 포인트, 남은 리스크를 정리한다.

8. [8_faq_and_decisions.md](./8_faq_and_decisions.md)
   "왜 native SQL로 바꿨는가", "다른 실행계획도 다 바꿔야 하는가" 같은 의사결정을 정리한다.

## 한 줄 요약

기존 검색은 `LOWER(...) LIKE '%카페%' OR EXISTS(...)` 구조라 인덱스를 못 탔고,
특히 `COUNT(*)`가 비쌌다. 이를 해결하기 위해 `places.search_text` 컬럼을 도입하고
MySQL `FULLTEXT INDEX ... WITH PARSER ngram`과 `MATCH ... AGAINST` 기반 검색으로 전환했다.
