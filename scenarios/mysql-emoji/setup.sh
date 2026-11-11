#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
db_start
sql <<'SQL'
CREATE DATABASE shop CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci;
USE shop;
CREATE TABLE reviews (id INT AUTO_INCREMENT PRIMARY KEY, book_id INT NOT NULL, author VARCHAR(80) NOT NULL, body TEXT NOT NULL, created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci;
SET SESSION cte_max_recursion_depth = 5000;
INSERT INTO reviews (book_id, author, body) WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 2000)
SELECT 1 + i % 300, ELT(1 + i % 4, 'Zoë', 'Jürgen', 'François', 'Inés'),
       ELT(1 + i % 4, 'Crème brûlée à la française, très bien écrit.', 'Größtenteils spannend, Übersetzung gelungen.', 'Señor García lo recomendó: ¡excelente!', 'Naïve but charming. Ça marche.') FROM n;
SQL
sql shop -N -e "select md5(group_concat(concat(id,':',author,':',body) order by id separator '|')) from reviews where id <= 2000" > /opt/sad/reviews.md5
db_stop
