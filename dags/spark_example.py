from airflow import DAG
from airflow.utils.dates import days_ago
from airflow.providers.apache.spark.operators.spark_submit import SparkSubmitOperator

with DAG(
    "spark_pi_demo",
    start_date=days_ago(1),
    schedule="@daily",
    catchup=False,
    tags=["spark", "demo"],
) as dag:
    spark_pi = SparkSubmitOperator(
        task_id="spark_pi",
        application="/opt/spark/examples/src/main/python/pi.py",
        conn_id="spark_default",  # set in Airflow Connections
        name="spark-pi",
        application_args=["10"],
    )
