FROM apache/airflow:2.10.4-python3.10

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Providers: Spark, Snowflake, Postgres
RUN pip install --no-cache-dir \
    apache-airflow-providers-apache-spark \
    apache-airflow-providers-snowflake \
    apache-airflow-providers-postgres

# Optional: include PySpark if you want spark-submit in this container
# RUN pip install --no-cache-dir pyspark==3.5.1
