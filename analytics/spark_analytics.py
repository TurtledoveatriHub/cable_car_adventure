"""
乐园过山车 - PySpark 离线分析作业

输入：游戏“数据分析”导出的 CSV（UTF-8，含表头）
输出：按关卡统计、碰撞类型统计、赛道碰撞热点、难度聚类

使用示例：
    spark-submit analytics/spark_analytics.py \
        --input export.csv \
        --output-dir analytics-output
"""
from __future__ import annotations

import argparse
import os
import sys

try:
    from pyspark.ml.clustering import KMeans
    from pyspark.ml.feature import StandardScaler, VectorAssembler
    from pyspark.sql import SparkSession
    from pyspark.sql import functions as F
except ImportError:
    print("缺少 pyspark，请先执行：python -m pip install -r analytics/requirements.txt")
    sys.exit(1)


NUMERIC_COLUMNS = [
    "passengers",
    "starting_passengers",
    "time_seconds",
    "stars",
    "collisions",
    "s",
    "track_progress",
    "speed",
    "difficulty",
    "obstacle_scale",
    "engine_scale",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Skywire telemetry analytics")
    parser.add_argument("--input", required=True, help="CSV exported by the game")
    parser.add_argument("--output-dir", required=True, help="directory for result CSV files")
    return parser.parse_args()


def load_events(spark: SparkSession, path: str):
    df = spark.read.option("header", True).option("inferSchema", False).csv(path)
    for name in NUMERIC_COLUMNS:
        if name in df.columns:
            df = df.withColumn(name, F.col(name).cast("double"))
    if "completed" in df.columns:
        df = df.withColumn(
            "completed_flag",
            F.when(F.lower(F.col("completed").cast("string")) == "true", F.lit(1.0)).otherwise(F.lit(0.0)),
        )
    else:
        df = df.withColumn("completed_flag", F.lit(0.0))
    return df


def level_summary(events):
    runs = events.filter(F.col("type") == "run_end")
    return (
        runs.groupBy("level_id", "level_name")
        .agg(
            F.count("*").alias("runs"),
            F.sum("completed_flag").alias("completed"),
            F.avg("passengers").alias("avg_passengers"),
            F.avg(F.when(F.col("completed_flag") > 0, F.col("time_seconds"))).alias("avg_time"),
            F.avg("collisions").alias("avg_collisions"),
            F.avg("obstacle_scale").alias("avg_obstacle_scale"),
        )
        .withColumn("completion_rate", F.col("completed") / F.col("runs"))
        .withColumn("collisions_per_run", F.col("avg_collisions"))
        .orderBy(F.desc("runs"))
    )


def collision_summary(events):
    collisions = events.filter(F.col("type") == "collision")
    return (
        collisions.groupBy("obstacle_type", "motion_type")
        .agg(F.count("*").alias("collisions"))
        .orderBy(F.desc("collisions"))
    )


def collision_hotspots(events, buckets: int = 20):
    collisions = events.filter(F.col("type") == "collision")
    return (
        collisions.withColumn(
            "bucket",
            F.least(
                F.lit(buckets - 1),
                F.greatest(F.lit(0), (F.col("track_progress") * F.lit(buckets)).cast("int")),
            ),
        )
        .groupBy("bucket")
        .agg(F.count("*").alias("collisions"))
        .orderBy("bucket")
    )


def cluster_levels(level_rows, spark: SparkSession, output_dir: str):
    if level_rows.count() < 2:
        return None
    features = level_rows.select(
        "level_id",
        "level_name",
        F.coalesce("completion_rate", F.lit(0.0)).alias("completion_rate"),
        F.coalesce("avg_time", F.lit(0.0)).alias("avg_time"),
        F.coalesce("collisions_per_run", F.lit(0.0)).alias("collisions_per_run"),
    ).na.fill(0.0)
    assembler = VectorAssembler(
        inputCols=["completion_rate", "avg_time", "collisions_per_run"],
        outputCol="raw_features",
    )
    vectorized = assembler.transform(features)
    scaler = StandardScaler(inputCol="raw_features", outputCol="features", withStd=True, withMean=True)
    scaled = scaler.fit(vectorized).transform(vectorized)
    k = min(3, scaled.count())
    model = KMeans(k=k, seed=42, featuresCol="features", predictionCol="cluster").fit(scaled)
    result = model.transform(scaled).select("level_id", "level_name", "cluster", "completion_rate", "avg_time", "collisions_per_run")
    result.coalesce(1).write.mode("overwrite").option("header", True).csv(os.path.join(output_dir, "level_clusters"))
    return result


def main() -> None:
    args = parse_args()
    os.makedirs(args.output_dir, exist_ok=True)
    spark = (
        SparkSession.builder.appName("SkywireRemakeAnalytics")
        .config("spark.sql.shuffle.partitions", "4")
        .getOrCreate()
    )
    events = load_events(spark, args.input)
    events.cache()

    levels = level_summary(events)
    levels.coalesce(1).write.mode("overwrite").option("header", True).csv(
        os.path.join(args.output_dir, "level_summary")
    )
    collisions = collision_summary(events)
    collisions.coalesce(1).write.mode("overwrite").option("header", True).csv(
        os.path.join(args.output_dir, "collision_types")
    )
    hotspots = collision_hotspots(events)
    hotspots.coalesce(1).write.mode("overwrite").option("header", True).csv(
        os.path.join(args.output_dir, "collision_hotspots")
    )
    cluster_levels(levels, spark, args.output_dir)

    print("== 按关卡统计 ==")
    levels.show(truncate=False)
    print("== 碰撞类型 ==")
    collisions.show(truncate=False)
    print("== 碰撞热点 ==")
    hotspots.show(20, truncate=False)
    print("输出目录：", os.path.abspath(args.output_dir))
    spark.stop()


if __name__ == "__main__":
    main()
