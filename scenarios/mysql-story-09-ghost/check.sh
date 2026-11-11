#!/bin/bash
. /usr/local/lib/sad/lib.sh
[ "$(nq 1 'select 1')" = 1 ] || fail "node1 is not running"
ty=$(nq 1 "select column_type from information_schema.columns where table_schema='bookstore' and table_name='books' and column_name='isbn'")
[ "$ty" = "varchar(17)" ] || fail "books.isbn is still $ty on node1"
[ "$(nq 1 "select is_nullable from information_schema.columns where table_schema='bookstore' and table_name='books' and column_name='isbn'")" = NO ] || fail "books.isbn must stay NOT NULL"
[ "$(nq 1 "select count(*) from information_schema.statistics where table_schema='bookstore' and table_name='books' and column_name='isbn' and seq_in_index=1")" -ge 1 ] || fail "there's no index on books.isbn"
[ "$(nq 1 "select count(*) from bookstore.books")" = "$(cat /opt/sad/books.count)" ] || fail "books has $(nq 1 'select count(*) from bookstore.books') rows; it had $(cat /opt/sad/books.count)"
left=$(nq 1 "select group_concat(table_name) from information_schema.tables where table_schema='bookstore' and table_name <> 'books'")
[ "$left" = NULL ] || [ -z "$left" ] || fail "leftover tables in bookstore: $left"
gt=$(nq 1 "select @@gtid_executed" | tr -d '\n')
[ "$(nq 2 "select wait_for_executed_gtid_set('$gt', 60)")" = 0 ] || fail "node2 hasn't caught up with node1"
[ "$(nq 2 "select column_type from information_schema.columns where table_schema='bookstore' and table_name='books' and column_name='isbn'")" = "varchar(17)" ] || fail "the change didn't reach node2"
# a blocking ALTER runs directly on `books`; gh-ost alters its _books_gho copy and swaps it in with RENAME
direct=$(cd /srv/mysql/node1 && for b in binlog.0*; do mysqlbinlog "$b" 2>/dev/null; done | grep -iE '^\s*alter\s+table\s+(`?bookstore`?\.)?`?books`?(\s|$)' | head -1)
[ -z "$direct" ] || fail "books was changed with a direct, blocking ALTER TABLE (it locks writes for the whole copy). Start a new box and do it online with gh-ost."
if [ -s /var/log/app/stalls.log ]; then
  fail "the app's writes were blocked by a lock for more than 5 s, $(wc -l < /var/log/app/stalls.log) time(s): a blocking change froze the shop. (Start a new box to reset the monitor.)"
fi
pass "books.isbn is VARCHAR(17) NOT NULL with an index, on both nodes, no rows lost, no leftovers, and the app never stalled"
