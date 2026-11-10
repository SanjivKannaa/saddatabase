#!/bin/bash
. /usr/local/lib/sad/lib.sh
pg_start || true   # expected to fail; the log tells the story
