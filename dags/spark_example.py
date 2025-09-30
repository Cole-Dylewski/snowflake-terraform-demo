import pendulum
from airflow import DAG
from airflow.providers.apache.spark.operators.spark_submit import SparkSubmitOperator

"""
Runs the built-in SparkPi example against your local Spark cluster started by Terraform.
No automatic schedule; trigger manually in the UI.
"""

with DAG(
    dag_id="spark_example",
    start_date=pendulum.datetime(2024, 1, 1, tz="UTC"),
    schedule=None,
    catchup=False,
    default_args={"owner": "airflow"},
    description="Demo: run Spark Pi on the local Spark cluster",
    tags=["demo", "spark"],
) as dag:

    spark_pi = SparkSubmitOperator(
        task_id="spark_pi",
        application="/opt/bitnami/spark/examples/src/main/python/pi.py",
        # Use the Spark Master in this project directly (no Airflow Connection needed)
        conf={"spark.master": "spark://spark-master:7077"},
        deploy_mode="client",
        verbose=True,
    )
