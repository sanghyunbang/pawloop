SET @table_exists := (
    SELECT COUNT(*)
    FROM information_schema.tables
    WHERE table_schema = DATABASE()
      AND table_name = 'places'
);

SET @index_exists := (
    SELECT COUNT(*)
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
      AND table_name = 'places'
      AND index_name = 'ft_places_search_text'
);

SET @ddl := IF(
    @table_exists = 0,
    'SELECT ''places table does not exist yet. Start the backend app first.'' AS message',
    IF(
        @index_exists = 0,
        'ALTER TABLE places ADD FULLTEXT INDEX ft_places_search_text (search_text)',
        'SELECT ''ft_places_search_text already exists.'' AS message'
    )
);

PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
