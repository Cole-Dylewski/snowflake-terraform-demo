from pyspark.sql import SparkSession

spark = SparkSession.builder.appName("wordcount-example").getOrCreate()
sc = spark.sparkContext

lines = sc.parallelize([
    "to be or not to be",
    "that is the question",
    "whether 'tis nobler in the mind to suffer",
])

counts = (lines.flatMap(lambda l: l.split())
               .map(lambda w: (w, 1))
               .reduceByKey(lambda a, b: a + b)
               .collect())

for w, n in sorted(counts, key=lambda x: (-x[1], x[0])):
    print(f"{w}\t{n}")

spark.stop()
