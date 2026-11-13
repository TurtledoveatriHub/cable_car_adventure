<script setup>
import { computed, ref } from "vue";
import { useEChart } from "../composables/useEChart";
import { number, percent } from "../utils/format";

const props = defineProps({
  levels: { type: Array, default: () => [] },
});

const chartEl = ref(null);

const option = computed(() => {
  const rows = props.levels.map((level) => ({
    ...level,
    x: Number(level.churn_rate) || 0,
    y: Number(level.heat_score) || 0,
    value: [Number(level.churn_rate) || 0, Number(level.heat_score) || 0],
    size: Math.max(12, Math.min(34, Math.sqrt((Number(level.plays) || 0) + (Number(level.runs) || 0) * 2) * 4.2)),
  }));
  const topNames = new Set([...rows].sort((a, b) => b.y - a.y).slice(0, 4).map((item) => item.level_id));
  return {
    animation: true,
    animationDuration: 1200,
    animationEasing: "elasticOut",
    grid: { left: 44, right: 20, top: 32, bottom: 38 },
    tooltip: {
      backgroundColor: "#fffdf3",
      borderColor: "#1d3557",
      borderWidth: 2,
      textStyle: { color: "#1d3557", fontSize: 10, fontWeight: 600 },
      formatter(params) {
        const item = params.data || {};
        return `<b>${item.name || ""}</b><br/><span style="color:#5c7288">作者 ${item.author_name || "—"}</span><br/>劝退率 <b style="color:#ff6b6b">${percent(item.churn_rate)}</b> · 热度 <b style="color:#c48a00">${item.heat_score}</b><br/>游玩 <b>${number(item.plays)}</b> · 进入 <b>${number(item.enters)}</b> · 通关率 ${percent(item.completion_rate)}`;
      },
    },
    xAxis: {
      type: "value",
      min: 0,
      max: 100,
      name: "劝退率",
      nameLocation: "middle",
      nameGap: 26,
      nameTextStyle: { color: "#345473", fontSize: 9, fontWeight: 600 },
      splitLine: { lineStyle: { color: "rgba(29,53,87,0.12)", type: "dashed" } },
      axisLabel: { color: "#5c7288", fontSize: 8, formatter: "{value}%" },
      axisLine: { show: true, lineStyle: { color: "#1d3557", width: 2 } },
    },
    yAxis: {
      type: "value",
      min: 0,
      max: 100,
      name: "热度",
      nameTextStyle: { color: "#345473", fontSize: 9, fontWeight: 600 },
      splitLine: { lineStyle: { color: "rgba(29,53,87,0.12)", type: "dashed" } },
      axisLabel: { color: "#5c7288", fontSize: 8 },
      axisLine: { show: true, lineStyle: { color: "#1d3557", width: 2 } },
    },
    graphic: [
      {
        type: "text",
        right: 25,
        top: 36,
        style: { text: "高热度 · 高劝退", fill: "rgba(255,107,107,0.7)", font: "9px sans-serif" },
      },
      {
        type: "text",
        left: 54,
        top: 36,
        style: { text: "高热度 · 低劝退", fill: "rgba(6,214,160,0.7)", font: "9px sans-serif" },
      },
    ],
    series: [
      {
        type: "scatter",
        symbolSize: (value, params) => params.data.size,
        itemStyle: {
          color: (params) => {
            const churn = Number(params.data.x) || 0;
            return churn >= 55 ? "#ff6b6b" : churn >= 30 ? "#ffd166" : "#06d6a0";
          },
          borderColor: "#1d3557",
          borderWidth: 2,
          shadowBlur: 12,
          shadowColor: "rgba(29,53,87,0.15)",
          shadowOffsetY: 4,
        },
        label: {
          show: true,
          formatter: (params) => (topNames.has(params.data.level_id) ? params.data.name : ""),
          position: "top",
          color: "#1d3557",
          fontSize: 8,
          fontWeight: 600,
          distance: 6,
        },
        emphasis: { scale: 1.2, label: { show: true } },
        markLine: {
          silent: true,
          symbol: "none",
          lineStyle: { color: "rgba(29,53,87,0.22)", type: "dashed", width: 1.5 },
          label: { show: false },
          data: [{ xAxis: 50 }, { yAxis: 50 }],
        },
        data: rows,
      },
    ],
  };
});

useEChart(chartEl, option);
</script>

<template>
  <div ref="chartEl" class="ugc-scatter" role="img" aria-label="UGC 劝退率与热度散点图"></div>
</template>

<style scoped>
.ugc-scatter { width: 100%; height: 318px; }
</style>
