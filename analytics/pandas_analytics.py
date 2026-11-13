"""
本地 pandas 分析（无需 Spark）。

与 spark_analytics.py 使用相同的 CSV 输入，输出：
- level_summary.csv
- collision_types.csv
- collision_hotspots.csv
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import pandas as pd


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output-dir", default="analytics-output")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    output = Path(args.output_dir)
    output.mkdir(parents=True, exist_ok=True)
    df = pd.read_csv(args.input, keep_default_na=False)
    for column in ("passengers", "starting_passengers", "time_seconds", "stars", "collisions", "s", "track_progress", "speed"):
        if column in df.columns:
            df[column] = pd.to_numeric(df[column], errors="coerce").fillna(0.0)
    df["completed_bool"] = df.get("completed", "").astype(str).str.lower() == "true"

    runs = df[df["type"] == "run_end"].copy()
    if runs.empty:
        print(json.dumps({"ok": False, "error": "no run_end events"}))
        return
    runs["is_completed"] = runs["completed_bool"].astype(int)
    runs["completed_time"] = runs["time_seconds"].where(runs["is_completed"] == 1)
    grouped = runs.groupby(["level_id", "level_name"], dropna=False).agg(
        runs=("type", "size"),
        completed=("is_completed", "sum"),
        avg_passengers=("passengers", "mean"),
        avg_time=("completed_time", "mean"),
        collisions=("collisions", "sum"),
    ).reset_index()
    grouped["avg_time"] = grouped["avg_time"].fillna(0.0)
    grouped["completion_rate"] = grouped["completed"] / grouped["runs"]
    grouped["collisions_per_run"] = grouped["collisions"] / grouped["runs"]
    grouped.to_csv(output / "level_summary.csv", index=False, encoding="utf-8-sig")

    collisions = df[df["type"] == "collision"].copy()
    if collisions.empty:
        collision_types = pd.DataFrame(columns=["obstacle_type", "motion_type", "collisions"])
        hotspots = pd.DataFrame(columns=["bucket", "collisions"])
    else:
        collision_types = collisions.groupby(["obstacle_type", "motion_type"], dropna=False).size().reset_index(name="collisions")
        collisions["bucket"] = (pd.to_numeric(collisions["track_progress"], errors="coerce").fillna(0.0) * 20).clip(0, 19).astype(int)
        hotspots = collisions.groupby("bucket").size().reset_index(name="collisions").sort_values("bucket")
    collision_types.to_csv(output / "collision_types.csv", index=False, encoding="utf-8-sig")
    hotspots.to_csv(output / "collision_hotspots.csv", index=False, encoding="utf-8-sig")

    print(json.dumps({
        "ok": True,
        "runs": int(len(runs)),
        "collisions": int(len(collisions)),
        "output": str(output.resolve()),
        "levels": grouped.to_dict(orient="records"),
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
