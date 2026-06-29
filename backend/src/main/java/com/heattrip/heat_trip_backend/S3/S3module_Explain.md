## S3 업로드 모듈 가이드 
(/src/main/java/com/heattrip/heat_trip_backend/S3)

### 1. 디렉토리 구조

com/heattrip/heat_trip_backend/s3
 ├─ FileStorage.java             # 업로드 추상화(인터페이스)
 ├─ StoredObject.java            # 업로드 결과 DTO (key, url, contentType, size)
 ├─ UploadCategory.java          # 업로드 범주(경로/용량/타입 정책)
 ├─ UploadRequest.java           # 업로드 요청 DTO (category, ownerId, subPath)
 ├─ KeyStrategy.java             # S3 키 생성 전략 인터페이스
 ├─ DefaultKeyStrategy.java      # 기본 키 전략(yyyy/MM + UUID + 파일명 sanitize)
 ├─ UploadValidator.java         # 업로드 검증 인터페이스
 ├─ ImageValidator.java          # 이미지 전용 검증(타입/사이즈)
 ├─ UrlMapper.java               # key ↔ CloudFront URL 변환
 └─ S3FileStorageService.java    # Amazon S3 구현체(FileStorage)

### 2. 설명

### 2.1 FileStorage (추상화 계층)

upload(Multipartfile, UploadRequest) -> StoredObject
컨트롤러에서는 FileStorage만 의존. (이걸 S3, 로컬, GCS로도 교체 가능)

### 2.2 UploadCategory (정책 테이블)

각 기능별 경로 prfix 
허용 MIME 타입
최대 크기 정의

- 기본 제공 :
JOURNEY_IMAGE: journeys/ (10MB, jpeg/png/webp/gif)
PROFILE_IMAGE: profiles/ (5MB, jpeg/png/webp)
REVIEW_IMAGE : reviews/ (10MB, jpeg/png/webp)

확장 필요 시 : 새 범주가 필요하면 enum에 한 줄 추가

### 2.3 KeyStrategy (키 규칙)

기본 규칙:
prefix/ownerId/yyyy/MM/{optional subPath/}{UUID}_{sanitizedOriginalName}

예:
journeys/42/2025/09/8f3e..._trip_photo.jpg
--> S3에 저런식으로 저장되서 폴더별로 관리 하기 쉬움

### 2.4 UploadValidator

빈 파일, 최대 크기 초과, 허용되지 않은 타입 차단.
이미지 이외(문서, 동영상 등)는 별도 Validator 구현 가능.

### 2.5 UrlMapper (표준 URL 변환)

DB에는 key만 저장 권장. (CDN 교체/도메인 변경 대비)
응답/뷰에는 CloudFrontDomain + "/" + key를 사용.

---

### 3. 동작 흐름

1. 컨트롤러가 MultipartFile과 업로드 컨텍스트(카테고리, ownerId, subPath)를 생성

2. FileStorage.upload(file, UploadRequest) 호출

3. ImageValidator가 타입/사이즈 검증

4. DefaultKeyStrategy가 키 생성

5. S3FileStorageService가 PutObjectRequest로 업로드

6. StoredObject(key, url, contentType, size) 반환

7. 컨트롤러는 응답에는 url 포함, DB에는 key 저장(권장)