from airflow import DAG
from airflow.utils.dates import days_ago
from airflow.providers.snowflake.operators.snowflake import SnowflakeOperator

with DAG(
    "snowflake_heartbeat",
    start_date=days_ago(1),
    schedule=None,
    catchup=False,
    tags=["snowflake", "demo"],
) as dag:
    ping = SnowflakeOperator(
        task_id="sf_version",
        sql="SELECT CURRENT_VERSION()",
        snowflake_conn_id="snowflake_default",  # set in Airflow Connections
    )
