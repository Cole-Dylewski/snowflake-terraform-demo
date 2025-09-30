import pendulum
from airflow import DAG
from airflow.providers.common.sql.operators.sql import SQLExecuteQueryOperator

"""
Minimal Snowflake example using the generic SQL operator.
Requires an Airflow Connection named `snowflake_default` with your account/warehouse/db/role.
"""

with DAG(
    dag_id="snowflake_example",
    start_date=pendulum.datetime(2024, 1, 1, tz="UTC"),
    schedule=None,
    catchup=False,
    default_args={"owner": "airflow"},
    description="Demo: simple query on Snowflake via generic SQL operator",
    tags=["demo", "snowflake"],
) as dag:

    run_query = SQLExecuteQueryOperator(
        task_id="run_query",
        conn_id="snowflake_default",   # Configure this in the Airflow UI / Connections
        sql="SELECT CURRENT_TIMESTAMP();",
    )
