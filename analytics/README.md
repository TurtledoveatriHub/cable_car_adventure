# 离线分析模块

游戏内“数据分析”页可导出原始行为事件：

```text
user://analytics/export.csv
```

Windows 下对应路径通常在：

```text
C:\Users\<user>\AppData\Roaming\Godot\app_userdata\乐园过山车：复刻版\analytics\export.csv
```

## 本地 pandas

```powershell
python -m pip install pandas
python analytics/pandas_analytics.py --input export.csv --output-dir analytics-output
```

输出：

- `level_summary.csv`
- `collision_types.csv`
- `collision_hotspots.csv`

## PySpark

```powershell
python -m pip install -r analytics/requirements.txt
spark-submit analytics/spark_analytics.py `
  --input export.csv `
  --output-dir analytics-output-spark
```

PySpark 作业额外包含关卡难度 KMeans 聚类：

特征：

- 通关率；
- 平均通关用时；
- 每局碰撞数。

输出 `level_clusters/`。

## 推荐生产链路

```text
TelemetryService
  → HTTP 批量上报 / Kafka producer
  → Kafka / Flume
  → HDFS / 对象存储
  → Spark SQL + MLlib
  → 指标库 / 分析看板 / 难度推荐
```

当前仓库实现的是客户端采集、本地聚合、CSV 导出与离线分析脚本；部署级消息队列与数仓属于平台接入阶段。
