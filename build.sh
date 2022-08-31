#!/bin/bash

# default configuration
# user: "postgres"
# database: "postgres"
# host: "localhost"
# primary port: "5432"
# data scale: 1
pg_user=postgres
pg_database=postgres
pg_host=localhost
pg_port=5432
data_scale=10
is_run=-1
test_case=18
clean=
option=""

usage () {
cat <<EOF

  1) Use default configuration to build
  ./build.sh
  2) Use limited configuration to build
  ./build.sh --user=postgres --db=postgres --host=localhost --port=5432 --scale=1
  3) Run the test case
  ./build.sh --run
  4) Run the target test case
  ./build.sh --run=3. run the 3rd case.
  5) Run the target test case with option
  ./build.sh --run --option="set polar_enable_px = on;"
  6) Clean the test data. This step will drop the database or tables, remove csv
  and tbl files
  ./build.sh --clean
  7) Quick build TPC-H with 100MB scale of data
  ./build.sh --scale=0.1

EOF
  exit 0;
}

for arg do
  val=`echo "$arg" | sed -e 's;^--[^=]*=;;'`

  case "$arg" in
    --user=*)                   pg_user="$val";;
    --db=*)                     pg_database="$val";;
    --host=*)                   pg_host="$val";;
    --port=*)                   pg_port="$val";;
    --scale=*)                  data_scale="$val";;
    --run)                      is_run=on ;;
    --run=*)                    is_run=on;
                                test_case="$val"
                                ;;
    --option=*)                 option="$val";;
    --clean)                    clean=on ;;
    -h|--help)                  usage ;;
    *)                          echo "wrong options : $arg";
                                exit 1
                                ;;
  esac
done

export PGPORT=$pg_port
export PGHOST=$pg_host
export PGDATABASE=$pg_database
export PGUSER=$pg_user

function gen_query_sql() {
    DIR=.
    rm -rf $DIR/finals
    mkdir $DIR/finals
    cp $DIR/queries/*.sql $DIR
    for FILE in $(find $DIR -maxdepth 1 -name "[0-9]*.sql")
    do
        DIGIT=$(echo $FILE | tr -cd '[[:digit:]]')
        ./qgen $DIGIT > $DIR/finals/$DIGIT.sql
        sed 's/^select/explain select/' $DIR/finals/$DIGIT.sql > $DIR/finals/$DIGIT.explain.sql
    done
    rm *.sql
}

function run_query_sql() {
    DIR=.
    if [[ $test_case -ne "-1" && $test_case -ne "on" ]]
    then
        echo "####################### $test_case.sql ###########################"
        echo "####################### $test_case.sql ###########################" >> $DIR/result
        psql -c "$option" -c "\timing" -f $DIR/finals/$test_case.explain.sql -qa >> $DIR/result
        psql -c "$option" -c "\timing" -f $DIR/finals/$test_case.sql -qa >> $DIR/result
    else
        for i in `seq 1 22`
        do
            echo "####################### $i.sql ###########################"
            echo "####################### $i.sql ###########################" >> $DIR/result
            psql -c "$option" -c "\timing" -f $DIR/finals/$i.explain.sql -qa >> $DIR/result
            psql -c "$option" -c "\timing" -f $DIR/finals/$i.sql -qa >> $DIR/result
        done
    fi
}

# run the tpch test
if [[ $is_run == "on" ]];
then
  run_query_sql;
  exit;
fi

# clean the tpch test data
if [[ $clean == "on" ]];
then
  make clean
  if [[ $pg_database == "postgres" ]];
  then
    echo "drop all the tpch tables"
    psql -c "drop table customer cascade"
    psql -c "drop table lineitem cascade"
    psql -c "drop table nation cascade"
    psql -c "drop table orders cascade"
    psql -c "drop table part cascade"
    psql -c "drop table partsupp cascade"
    psql -c "drop table region cascade"
    psql -c "drop table supplier cascade"
  else
    echo "drop the tpch database: $PGDATABASE"
    psql -c "drop database $PGDATABASE" -d postgres
  fi
  exit;
fi

###################### PHASE 1: compile ######################
make -f makefile.suite

##################### PHASE 2: generate data ######################
rm -rf *.tbl
./dbgen -s $data_scale

###################### PHASE 3: create table ######################
if [[ $PGDATABASE != "postgres" ]];
then
  echo "create the tpch database: $PGDATABASE"
  psql -c "create database $PGDATABASE" -d postgres
fi
psql -f dss.ddl

###################### PHASE 4: load data ######################
psql -c "\COPY nation FROM 'nation.tbl' WITH (FORMAT csv, DELIMITER '|');"
psql -c "\COPY region FROM 'region.tbl' WITH (FORMAT csv, DELIMITER '|');"
psql -c "\COPY part FROM 'part.tbl' WITH (FORMAT csv, DELIMITER '|');"
psql -c "\COPY supplier FROM 'supplier.tbl' WITH (FORMAT csv, DELIMITER '|');"
psql -c "\COPY partsupp FROM 'partsupp.tbl' WITH (FORMAT csv, DELIMITER '|');"
psql -c "\COPY customer FROM 'customer.tbl' WITH (FORMAT csv, DELIMITER '|');"
psql -c "\COPY orders FROM 'orders.tbl' WITH (FORMAT csv, DELIMITER '|');"
psql -c "\COPY lineitem FROM 'lineitem.tbl' WITH (FORMAT csv, DELIMITER '|');"

###################### PHASE 5: add primary and foreign key ######################
psql -f dss.ri

##################### PHASE 6: generate query sql in final dir ######################
gen_query_sql;
