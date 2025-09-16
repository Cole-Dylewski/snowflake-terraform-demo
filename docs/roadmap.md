# Impressive Spark-based Ingestion Architecture

## Showpiece Architecture

**REST APIs → Event Buffer (Kafka) → Spark Structured Streaming → Bronze (S3/MinIO, Delta/Parquet) → Quality (Great Expectations) → JDBC sink to `src` Postgres → Lineage & Metrics (Marquez + Prometheus/Grafana)**

### Core Focus

* **Decoupled & resilient:** REST fetchers are stateless producers; Spark is the scalable consumer.
* **Streaming mindset:** Even if sources are polled, you treat data as a stream (micro-batch).
* **Governance built-in:** Schema registry, data quality checks, lineage, and observability.
* **Lake + DB dual-target:** Land raw to object storage and hydrate Postgres for app/dev UX.

---

## Components to Add (Terraform-managed containers)

* **Spark**: spark-master + N spark-workers (standalone cluster)
* **Kafka stack**: Zookeeper/KRaft, Kafka broker, Schema Registry
* **REST fetchers**: Python services producing JSON to Kafka
* **Object store**: MinIO (S3-compatible)
* **Data quality**: Great Expectations
* **Lineage**: Marquez (OpenLineage)
* **Orchestration**: Airflow or Prefect
* **Observability**: Prometheus + Grafana
* **Secrets**: Vault or Docker secrets

---

## Data Flow

1. **Fetchers** poll APIs, attach headers (ETag/If-Modified-Since), publish JSON to Kafka.
2. **Spark Structured Streaming** consumes, validates schema, writes to:

   * **Bronze (S3/MinIO)**: Parquet/Delta with partitioned paths.
   * **Postgres**: upsert into `raw.api_events`.
3. **Great Expectations** runs on bronze/silver data.
4. **OpenLineage** tracks job → dataset lineage.
5. **Grafana** shows lag, throughput, errors.

---

## Postgres Tables

```sql
create schema if not exists raw;

create table if not exists raw.api_events (
  id bigserial primary key,
  source text not null,
  external_id text,
  payload jsonb not null,
  pulled_at timestamptz not null default now(),
  unique (source, external_id)
);
```

---

## Spark Structured Streaming Example

```python
from pyspark.sql import SparkSession, functions as F
from pyspark.sql.types import StringType

spark = (SparkSession.builder
    .appName("rest_to_bronze_postgres")
    .config("spark.sql.shuffle.partitions", "8")
    .config("spark.sql.streaming.schemaInference", "true")
    .getOrCreate())

df = (spark.readStream
    .format("kafka")
    .option("kafka.bootstrap.servers", "kafka:9092")
    .option("subscribe", "events.github")
    .option("startingOffsets", "latest")
    .load())

json = F.col("value").cast(StringType())
events = spark.read.json(df.select(json).alias("value"))

events = (events
    .withColumn("source", F.lit("github"))
    .withColumn("ingest_ts", F.current_timestamp())
    .withColumn("external_id", F.coalesce(F.col("id").cast(StringType()),
                                          F.sha2(F.to_json(F.struct("*")), 256))))

bronze_query = (events
    .writeStream
    .format("delta")
    .option("checkpointLocation", "s3a://checkpoints/github_bronze")
    .option("path", "s3a://bronze/source=github/")
    .outputMode("append")
    .start())

def upsert_to_pg(batch_df, batch_id):
    (batch_df
     .select("source", "external_id", F.to_json(F.struct("*")).alias("payload"), "ingest_ts")
     .write
     .format("jdbc")
     .mode("append")
     .option("url", "jdbc:postgresql://src_db:5432/src")
     .option("dbtable", "raw.api_events_stage")
     .option("user", "src_user").option("password", "src_pass")
     .save())

pg_query = (events
    .writeStream
    .foreachBatch(upsert_to_pg)
    .option("checkpointLocation", "s3a://checkpoints/github_pg")
    .outputMode("update")
    .start())

spark.streams.awaitAnyTermination()
```

---

## Fetcher Highlights

* Async polling with aiohttp + backoff
* Pagination + rate-limit aware
* ETag caching
* Emits idempotency keys

---

## Production Niceties

* Schema Registry enforcement
* Great Expectations checkpoints
* OpenLineage lineage tracking
* Grafana dashboards for metrics
* Backfill replayer service
* Exactly-once semantics (Kafka keys + Postgres unique constraint)

---

## Integration Steps

1. Add Terraform modules for Spark, Kafka, MinIO, orchestration, lineage, observability.
2. Create `raw.api_events` and staging tables in Postgres.
3. Build `fetcher` and `spark-job` images.
4. Wire `.env` secrets into Terraform.
5. Add Makefile targets for infra, bronze demo, and backfills.

---

## Optional Twist

* Extend sinks to **Snowflake** using Snowflake Kafka Connector or Spark Snowflake connector.
* Demo a pipeline: REST → Kafka → Spark → MinIO (Delta) + Postgres + Snowflake.
