#!/bin/bash
. /usr/local/lib/sad/lib.sh
q "select 1" | grep -q 1 || fail "MySQL is not running"
[ "$(q "select md5(group_concat(concat(id,':',author,':',body) order by id separator '|')) from reviews where id <= 2000" shop)" = "$(cat /opt/sad/reviews.md5)" ] || fail "existing reviews changed: accents or text were mangled (or rows lost)"
e='Loved it 📚🔥 ✓'
id=$(mysql -u sadgrader --default-character-set=utf8mb4 -N -B shop -e "INSERT INTO reviews (book_id, author, body) VALUES (1, 'Grader', '$e'); SELECT LAST_INSERT_ID();" 2>&1)
[[ "$id" =~ ^[0-9]+$ ]] || fail "an emoji review still can't be saved: $id"
back=$(mysql -u sadgrader --default-character-set=utf8mb4 -N -B shop -e "SELECT body FROM reviews WHERE id = $id")
q "delete from reviews where author = 'Grader'" shop >/dev/null
[ "$back" = "$e" ] || fail "the emoji review was saved but came back as '$back'"
for c in author body; do
  cs=$(q "select character_set_name from information_schema.columns where table_schema='shop' and table_name='reviews' and column_name='$c'")
  [ "$cs" = utf8mb4 ] || fail "reviews.$c is still $cs"
done
[ "$(q "select default_character_set_name from information_schema.schemata where schema_name='shop'")" = utf8mb4 ] || fail "the shop database still defaults to utf8mb3: the next new table will have the same problem"
pass "emoji reviews work, every old review is byte-for-byte intact, and shop defaults to utf8mb4"
