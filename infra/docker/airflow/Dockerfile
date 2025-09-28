# Airflow 3.1.0 image built for Python 3.13
# (multi-arch images published by the Airflow project)
FROM apache/airflow:3.1.0-python3.13

# Helpful runtime flags
ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Match provider installs to the exact Airflow/Python constraints
ARG AIRFLOW_VERSION=3.1.0
ARG PYTHON_MINOR=3.13
ENV AIRFLOW_VERSION=${AIRFLOW_VERSION} \
    PYTHON_MINOR=${PYTHON_MINOR} \
    AIRFLOW_CONSTRAINTS="https://raw.githubusercontent.com/apache/airflow/constraints-${AIRFLOW_VERSION}/constraints-${PYTHON_MINOR}.txt"

# Install providers: Spark, Snowflake, Postgres
# (you can add others to this same pip command as needed)
RUN pip install --no-cache-dir --constraint "${AIRFLOW_CONSTRAINTS}" \
    apache-airflow-providers-apache-spark \
    apache-airflow-providers-snowflake \
    apache-airflow-providers-postgres

# Optional: include PySpark if you want spark-submit inside this container
# NOTE: only needed if this image will run Spark drivers; not required for remote Spark via connection
# RUN pip install --no-cache-dir --constraint "${AIRFLOW_CONSTRAINTS}" "pyspark==3.5.1"
