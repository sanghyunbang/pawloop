-- 더미 장소 데이터 10,000건 생성
-- k6 explore-read-baseline 테스트용
-- contentid 범위: 9000001 ~ 9010000 (실제 관광 API 데이터와 충돌 없음)
-- 기존 더미 데이터가 있으면 먼저 삭제 후 재삽입

DELETE FROM places WHERE contentid BETWEEN 9000001 AND 9010000;

DROP PROCEDURE IF EXISTS seed_dummy_places;

DELIMITER //
CREATE PROCEDURE seed_dummy_places()
BEGIN
  DECLARE i INT DEFAULT 1;

  -- 검색 키워드 배열 (k6 스크립트 기본값: 서울,부산,카페,바다)
  DECLARE titles JSON DEFAULT JSON_ARRAY(
    '서울 북촌 한옥마을', '부산 해운대 해수욕장', '강릉 카페거리',
    '제주 바다 전망대', '경주 불국사', '인천 송도 공원',
    '서울 남산 타워', '부산 광안리 카페', '속초 바다 횟집',
    '서울 홍대 카페', '부산 감천문화마을', '강원 바다 펜션',
    '서울 이태원 레스토랑', '제주 카페 올레길', '부산 태종대',
    '서울 한강 공원', '부산 자갈치 시장', '강릉 바다 카페',
    '제주 성산일출봉', '서울 경복궁'
  );

  DECLARE areas JSON DEFAULT JSON_ARRAY(1,2,3,4,5,6,7,31,32,33,34,35,36,37,38,39);
  DECLARE cat1s JSON DEFAULT JSON_ARRAY('A01','A02','A03','A04','A05');
  DECLARE cat2s JSON DEFAULT JSON_ARRAY('A0101','A0201','A0301','A0401','A0501');
  DECLARE cat3s JSON DEFAULT JSON_ARRAY('A01011','A02010','A03011','A04011','A05010');
  DECLARE typids JSON DEFAULT JSON_ARRAY('12','14','15','25','28','32','38','39');

  DECLARE title_idx INT;
  DECLARE area_idx  INT;
  DECLARE cat_idx   INT;
  DECLARE typ_idx   INT;
  DECLARE keyword   VARCHAR(20);

  WHILE i <= 10000 DO
    SET title_idx = (i - 1) MOD JSON_LENGTH(titles);
    SET area_idx  = (i - 1) MOD JSON_LENGTH(areas);
    SET cat_idx   = (i - 1) MOD JSON_LENGTH(cat1s);
    SET typ_idx   = (i - 1) MOD JSON_LENGTH(typids);

    -- 검색어에 서울/부산/카페/바다가 고르게 섞이도록
    SET keyword = ELT((i MOD 4) + 1, '서울', '부산', '카페', '바다');

    INSERT INTO places (
      contentid, title, addr1, addr2, zipcode,
      mapx, mapy,
      firstimage, firstimage2,
      cat1, cat2, cat3,
      areacode, sigungucode,
      tel, contenttypeid,
      search_text,
      createdtime, modifiedtime, mlevel
    ) VALUES (
      9000000 + i,
      CONCAT(JSON_UNQUOTE(JSON_EXTRACT(titles, CONCAT('$[', title_idx, ']'))), ' ', i),
      CONCAT('더미시 더미구 더미로 ', i, '번길'),
      CONCAT(i, '호'),
      LPAD(MOD(10000 + i, 100000), 5, '0'),
      126.5 + (i MOD 300) * 0.01,
      34.5  + (i MOD 200) * 0.01,
      NULL,
      NULL,
      JSON_UNQUOTE(JSON_EXTRACT(cat1s, CONCAT('$[', cat_idx, ']'))),
      JSON_UNQUOTE(JSON_EXTRACT(cat2s, CONCAT('$[', cat_idx, ']'))),
      JSON_UNQUOTE(JSON_EXTRACT(cat3s, CONCAT('$[', cat_idx, ']'))),
      JSON_UNQUOTE(JSON_EXTRACT(areas, CONCAT('$[', area_idx, ']'))),
      (i MOD 10) + 1,
      NULL,
      JSON_UNQUOTE(JSON_EXTRACT(typids, CONCAT('$[', typ_idx, ']'))),
      CONCAT(
        JSON_UNQUOTE(JSON_EXTRACT(titles, CONCAT('$[', title_idx, ']'))),
        ' ', keyword, ' ',
        JSON_UNQUOTE(JSON_EXTRACT(cat1s, CONCAT('$[', cat_idx, ']')))
      ),
      DATE_SUB(NOW(), INTERVAL (10000 - i) HOUR),
      DATE_SUB(NOW(), INTERVAL (10000 - i) HOUR),
      '5'
    );

    SET i = i + 1;
  END WHILE;
END //
DELIMITER ;

CALL seed_dummy_places();
DROP PROCEDURE IF EXISTS seed_dummy_places;

SELECT COUNT(*) AS dummy_places_count FROM places WHERE contentid BETWEEN 9000001 AND 9010000;
