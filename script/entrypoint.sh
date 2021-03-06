#!/usr/bin/env bash

TRY_LOOP="20"

: "${REDIS_HOST:="redis"}"
: "${REDIS_PORT:="6379"}"
: "${REDIS_PASSWORD:=""}"

: "${POSTGRES_HOST:="postgres"}"
: "${POSTGRES_PORT:="5432"}"
: "${POSTGRES_USER:="airflow"}"
: "${POSTGRES_PASSWORD:="airflow"}"
: "${POSTGRES_DB:="airflow"}"

# Defaults and back-compat
: "${AIRFLOW_HOME:="/usr/local/airflow"}"
: "${AIRFLOW__CORE__FERNET_KEY:=${FERNET_KEY:=$(python -c "from cryptography.fernet import Fernet; FERNET_KEY = Fernet.generate_key().decode(); print(FERNET_KEY)")}}"
: "${AIRFLOW__CORE__EXECUTOR:=${EXECUTOR:-Sequential}Executor}"

echo "export AIRFLOW_HOME=${AIRFLOW_HOME}" >> ~/.bashrc
# might change later in this script
#export AIRFLOW__CELERY__BROKER_URL
# echo "export AIRFLOW__CELERY__BROKER_URL=${AIRFLOW__CELERY__BROKER_URL}" >> ~/.bashrc
echo "export AIRFLOW__CELERY__RESULT_BACKEND=${AIRFLOW__CELERY__RESULT_BACKEND}" >> ~/.bashrc
echo "export AIRFLOW__CORE__EXECUTOR=${AIRFLOW__CORE__EXECUTOR}" >> ~/.bashrc
echo "export AIRFLOW__CORE__FERNET_KEY=${AIRFLOW__CORE__FERNET_KEY}" >> ~/.bashrc
# might change later in this script
#export AIRFLOW__CORE__LOAD_EXAMPLES
# echo "export AIRFLOW__CORE__LOAD_EXAMPLES=${AIRFLOW__CORE__LOAD_EXAMPLES}" >> ~/.bashrc
echo "export AIRFLOW__CORE__SQL_ALCHEMY_CONN=${AIRFLOW__CORE__SQL_ALCHEMY_CONN}" >> ~/.bashrc

export \
  AIRFLOW_HOME \
  AIRFLOW__CELERY__BROKER_URL \
  AIRFLOW__CELERY__RESULT_BACKEND \
  AIRFLOW__CORE__EXECUTOR \
  AIRFLOW__CORE__FERNET_KEY \
  AIRFLOW__CORE__LOAD_EXAMPLES \
  AIRFLOW__CORE__SQL_ALCHEMY_CONN \

# Load DAGs exemples (default: Yes)
if [[ -z "$AIRFLOW__CORE__LOAD_EXAMPLES" && "${LOAD_EX:=n}" == n ]]
then
  AIRFLOW__CORE__LOAD_EXAMPLES=False
fi
# echo "export AIRFLOW__CORE__LOAD_EXAMPLES=${AIRFLOW__CORE__LOAD_EXAMPLES}" >> ~/.bashrc

# source ~/.bashrc

# Install custom python package if requirements.txt is present
if [ -e "/requirements.txt" ]; then
    $(command -v pip) install --user -r /requirements.txt
fi

if [ -n "$REDIS_PASSWORD" ]; then
    REDIS_PREFIX=:${REDIS_PASSWORD}@
else
    REDIS_PREFIX=
fi
echo "export REDIS_PREFIX=${REDIS_PREFIX}" >> ~/.bashrc

wait_for_port() {
  local name="$1" host="$2" port="$3"
  local j=0
  while ! nc -z "$host" "$port" >/dev/null 2>&1 < /dev/null; do
    j=$((j+1))
    if [ $j -ge $TRY_LOOP ]; then
      echo >&2 "$(date) - $host:$port still not reachable, giving up"
      exit 1
    fi
    echo "$(date) - waiting for $name... $j/$TRY_LOOP"
    sleep 5
  done
}

if [ "$AIRFLOW__CORE__EXECUTOR" != "SequentialExecutor" ]; then
  AIRFLOW__CORE__SQL_ALCHEMY_CONN="postgresql+psycopg2://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB"
  echo "export AIRFLOW__CORE__SQL_ALCHEMY_CONN=${AIRFLOW__CORE__SQL_ALCHEMY_CONN}" >> ~/.bashrc
  AIRFLOW__CELERY__RESULT_BACKEND="db+postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB"
  wait_for_port "Postgres" "$POSTGRES_HOST" "$POSTGRES_PORT"
  echo "export AIRFLOW__CELERY__RESULT_BACKEND=${AIRFLOW__CELERY__RESULT_BACKEND}" >> ~/.bashrc
fi

if [ "$AIRFLOW__CORE__EXECUTOR" = "CeleryExecutor" ]; then
  AIRFLOW__CELERY__BROKER_URL="redis://$REDIS_PREFIX$REDIS_HOST:$REDIS_PORT/1"
  wait_for_port "Redis" "$REDIS_HOST" "$REDIS_PORT"
fi
echo "export AIRFLOW__CELERY__BROKER_URL=${AIRFLOW__CELERY__BROKER_URL}" >> ~/.bashrc

#source ~/.bashrc

case "$1" in
  webserver)
    airflow initdb
    if [ "$AIRFLOW__CORE__EXECUTOR" = "LocalExecutor" ] || [ "$AIRFLOW__CORE__EXECUTOR" = "SequentialExecutor" ]; then
      # With the "Local" and "Sequential" executors it should all run in one container.
      airflow scheduler &
    fi
      #Importing variables
    echo "Importing variables" 
    if [[ "$ENVIRONMENT" = "test" ]]; then
      echo "ambiente test"
      if [ -e "${AIRFLOW_HOME}/variables_test.json" ]; then
        echo "existen vars test"
        airflow variables --import /variables_test.json
      fi
    else
      echo "no"
      if [ -e "vars/variables_pro.json" ]; then
        airflow variables --import /variables_pro.json
      fi
    fi
    #Importing schemas variables
    if [ -e "vars/schemas.json" ]; then
      airflow variables --import /schemas.json
    fi
      # Create google cloud connection
    airflow connections --add --conn_id=bigquery_dev --conn_type=google_cloud_platform --conn_extra='{ "extra__google_cloud_platform__key_path":"/usr/local/airflow/dags/config/gc.json", "extra__google_cloud_platform__project": "st-etl-2019", "extra__google_cloud_platform__scope": "https://www.googleapis.com/auth/cloud-platform"}'
    exec airflow webserver
    ;;
  worker|scheduler)
    # To give the webserver time to run initdb.
    sleep 10
    exec airflow "$@"
    ;;
  flower)
    sleep 10
    exec airflow "$@"
    ;;
  version)
    exec airflow "$@"
    ;;
  *)
    # The command is something like bash, not an airflow subcommand. Just run it in the right environment.
    exec "$@"
    ;;
esac