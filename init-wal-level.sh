#!/bin/bash
set -e
echo "wal_level = logical" >>"$PGDATA/postgresql.conf"
