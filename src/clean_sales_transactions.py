import sys
import boto3
from awsglue.utils import getResolvedOptions
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.context import SparkContext
from pyspark.sql import functions as F
from pyspark.sql.window import Window

# --- Job setup ---------------------------------------------------------
args = getResolvedOptions(
    sys.argv,
    ["JOB_NAME", "RAW_PATH", "CURATED_PATH", "QUARANTINE_PATH", "SNS_TOPIC_ARN"]
)

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args["JOB_NAME"], args)

DQ_FAILURE_THRESHOLD = 0.10  # fail the job if more than 10% of records are bad

# --- Read raw data -------------------------------------------------------
raw_df = spark.read.csv(args["RAW_PATH"], header=True, inferSchema=True)

raw_df.printSchema()
raw_df.show(5)



raw_df = raw_df.withColumn(
    "order_date_parsed",
    F.coalesce(
        F.to_date(F.col("order_date"), "yyyy-MM-dd"),
        F.to_date(F.col("order_date"), "dd/MM/yyyy")
    )
)



# --- Data quality: flag missing/invalid fields -----------------------------
flagged_df = raw_df.withColumn(
    "dq_issue",
    F.when(F.col("order_id").isNull() | (F.trim(F.col("order_id")) == ""), "missing_order_id")
    .when(F.col("customer_id").isNull() | (F.trim(F.col("customer_id")) == ""), "missing_customer_id")
    .when(F.col("product_sku").isNull() | (F.trim(F.col("product_sku")) == ""), "missing_product_sku")
    .when(F.col("order_date_parsed").isNull(), "missing_or_invalid_order_date")
    .when(F.col("quantity").isNull() | (F.col("quantity") <= 0), "invalid_quantity")
    .when(F.col("unit_price").isNull() | (F.col("unit_price") <= 0), "invalid_unit_price")
    .when(~F.col("currency").isin("GBP", "USD", "EUR"), "invalid_currency")
    .otherwise(None)
)

# --- Data quality: flag duplicate order_id ---------------------------------
window_spec = Window.partitionBy("order_id").orderBy(F.lit(1))
flagged_df = flagged_df.withColumn("dq_row_num", F.row_number().over(window_spec))

flagged_df = flagged_df.withColumn(
    "dq_issue",
    F.when(F.col("dq_issue").isNotNull(), F.col("dq_issue"))
     .when(F.col("dq_row_num") > 1, "duplicate_order_id")
     .otherwise(None)
)

# --- Split into clean vs quarantined --------------------------------------
clean_df = flagged_df.filter(F.col("dq_issue").isNull()).drop("dq_issue", "dq_row_num")
quarantine_df = flagged_df.filter(F.col("dq_issue").isNotNull()).drop("dq_row_num")

total_count = flagged_df.count()
bad_count = quarantine_df.count()
bad_rate = bad_count / total_count if total_count > 0 else 0

print(f"Total records: {total_count}, quarantined: {bad_count}, bad rate: {bad_rate:.2%}")

# --- Write quarantined records + notify -----------------------------------
if bad_count > 0:
    quarantine_df.write.mode("overwrite").option("header", True).csv(args["QUARANTINE_PATH"])

    sns = boto3.client("sns")
    message = (
        f"Data quality check flagged {bad_count} of {total_count} records "
        f"({bad_rate:.2%}) in this pipeline run.\n"
        f"Quarantined records written to: {args['QUARANTINE_PATH']}\n"
        f"Please review."
    )
    sns.publish(
        TopicArn=args["SNS_TOPIC_ARN"],
        Subject="Sales transactions pipeline - data quality issues found",
        Message=message
    )

# --- Fail the job if the bad-record rate is too high ----------------------
if bad_rate > DQ_FAILURE_THRESHOLD:
    job.commit()
    raise Exception(
        f"Data quality check failed: {bad_rate:.2%} of records were bad "
        f"(threshold: {DQ_FAILURE_THRESHOLD:.0%}). See quarantine output and SNS alert for details."
    )

# --- Write clean data to curated zone, partitioned -------------------------
clean_df = clean_df.drop("order_date") \
                    .withColumnRenamed("order_date_parsed", "order_date")

clean_df = clean_df.withColumn("order_year", F.year("order_date")) \
                    .withColumn("order_month", F.month("order_date"))

clean_df.write.mode("overwrite") \
    .partitionBy("order_year", "order_month", "region") \
    .parquet(args["CURATED_PATH"])

job.commit()