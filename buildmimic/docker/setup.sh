#!/bin/bash

echo 'CREATING MIMIC ... '

# this flag allows us to initialize the docker repo without building the data
if [ $BUILD_MIMIC -eq 1 ]
then
echo "running create mimic user"

pg_ctl stop

pg_ctl -D "$PGDATA" \
	-o "-c listen_addresses='' -c checkpoint_timeout=600" \
	-w start

psql <<- EOSQL
    CREATE USER MIMIC WITH PASSWORD '$MIMIC_PASSWORD';
    CREATE DATABASE MIMIC OWNER MIMIC;
    \c mimic;
    CREATE SCHEMA MIMICIII;
		ALTER SCHEMA MIMICIII OWNER TO MIMIC;
EOSQL

# check for the admissions to set the extension
if [ -e "/mimic_data/ADMISSIONS.csv.gz" ]; then
  COMPRESSED=1
  EXT='.csv.gz'
elif [ -e "/mimic_data/ADMISSIONS.csv" ]; then
  COMPRESSED=0
  EXT='.csv'
else
  echo "Unable to find a MIMIC data file (ADMISSIONS) in /mimic_data"
  echo "Did you map a local directory using `docker run -v /path/to/mimic/data:/mimic_data` ?"
  exit 1
fi

# check for all the tables, exit if we are missing any
ALLTABLES='admissions callout caregivers chartevents cptevents datetimeevents d_cpt diagnoses_icd d_icd_diagnoses d_icd_procedures d_items d_labitems drgcodes icustays inputevents_cv inputevents_mv labevents microbiologyevents noteevents outputevents patients prescriptions procedureevents_mv procedures_icd services transfers'

for TBL in $ALLTABLES; do
  if [ ! -e "/mimic_data/${TBL^^}$EXT" ];
  then
    echo "Unable to find ${TBL^^}$EXT in /mimic_data"
    exit 1
  fi
  echo "Found all tables in /mimic_data - beginning import from $EXT files."
done

# checks passed - begin building the database
PG_VER=$(postgres -V | egrep -o -m 1 '[0-9]{1,}\.[0-9]{1,}')
if [ $${PG_VER:0:1} -eq 1 ]; then
echo "$0: running postgres_create_tables_pg10.sql"
psql --username "$POSTGRES_USER" --dbname mimic < /docker-entrypoint-initdb.d/buildmimic/postgres/postgres_create_tables_pg10.sql
else
echo "$0: running postgres_create_tables_pg.sql"
psql --username "$POSTGRES_USER" --dbname mimic < /docker-entrypoint-initdb.d/buildmimic/postgres/postgres_create_tables.sql
fi

if [ $COMPRESSED -eq 1 ]; then
echo "$0: running postgres_load_data_gz.sql"
psql --username "$POSTGRES_USER" --dbname mimic -v mimic_data_dir=/mimic_data < /docker-entrypoint-initdb.d/buildmimic/postgres/postgres_load_data_gz.sql
else
echo "$0: running postgres_load_data.sql"
psql --username "$POSTGRES_USER" --dbname mimic -v mimic_data_dir=/mimic_data < /docker-entrypoint-initdb.d/buildmimic/postgres/postgres_load_data.sql
fi

echo "$0: running postgres_add_indexes.sql"
psql --username "$POSTGRES_USER" --dbname mimic < /docker-entrypoint-initdb.d/buildmimic/postgres/postgres_add_indexes.sql

echo "$0: running postgres_add_constraints.sql"
psql --username "$POSTGRES_USER" --dbname mimic < /docker-entrypoint-initdb.d/buildmimic/postgres/postgres_add_constraints.sql


echo "$0: running postgres_checks.sql (all rows should return PASSED)"
psql --username "$POSTGRES_USER" --dbname mimic < /docker-entrypoint-initdb.d/buildmimic/postgres/postgres_checks.sql
fi

echo 'Done!'
