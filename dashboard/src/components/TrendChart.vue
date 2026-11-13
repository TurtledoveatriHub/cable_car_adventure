<script setup>
import { computed, ref } from "vue";
import { useEChart } from "../composables/useEChart";
import { number, shortDate } from "../utils/format";

const props = defineProps({
  trend: { type: Array, default: () => [] },
});

const chartEl = ref(null);
const labels = computed(() => props.trend.map((item) => shortDate(item.date)));

const option = computed(() => ({
  animation: true,
  animationDuration: 1500,
  animationDurationUpdate: 800,
  animationEasing: "cubicOut",
  color: ["#06d6a0", "#ffd166", "#ff6b6b", "#63b3ed"],
  grid: { left: 42, right: 48, top: 52, bottom: 30 },
  legend: {
    top: 1,
    right: 0,
    icon: "roundRect",
    itemWidth: 10,
    itemHeight: 7,
    itemGap: 15,
    textStyle: { color: "#345473", fontSize: 10, fontWeight: 600 },
  },
  tooltip: {
    trigger: "axis",
    backgroundColor: "#fffdf3",
    borderColor: "#1d3557",
    borderWidth: 2,
    padding: [8, 11],
    textStyle: { color: "#1d3557", fontSize: 10, fontWeight: 600 },
    axisPointer: { type: "line", lineStyle: { color: "#1d3557", type: "dashed", width: 1.5 } },
    formatter(params) {
      const index = params?.[0]?.dataIndex ?? 0;
      const row = props.trend[index] || {};
      const line = (label, value, color) => `<div style="display:flex;justify-content:space-between;gap:24px;font-weight:600"><span>${label}</span><b style="color:${color}">${value}</b></div>`;
      return `<div style="font-family:monospace;color:#5c7288;margin-bottom:5px">${row.date || ""}</div>`
        + line("游玩次数", number(row.runs), "#1d3557")
        + line("通关次数", number(row.completed), "#c48a00")
        + line("碰撞事件", number(row.collisions), "#ff6b6b")
        + line("通关率", `${Number(row.completion_rate || 0).toFixed(1)}%`, "#2b79b8");
    },
  },
  xAxis: {
    type: "category",
    boundaryGap: false,
    data: labels.value,
    axisLine: { lineStyle: { color: "#1d3557", width: 2 } },
    axisTick: { show: false },
    axisLabel: { color: "#5c7288", fontSize: 9, margin: 12, fontWeight: 600 },
  },
  yAxis: [
    {
      type: "value",
      minInterval: 1,
      splitLine: { lineStyle: { color: "rgba(29,53,87,0.12)", type: "dashed" } },
      axisLabel: { color: "#5c7288", fontSize: 9 },
      axisLine: { show: true, lineStyle: { color: "#1d3557", width: 2 } },
    },
    {
      type: "value",
      min: 0,
      max: 100,
      splitLine: { show: false },
      axisLabel: { color: "#2b79b8", fontSize: 9, formatter: "{value}%" },
      axisLine: { show: true, lineStyle: { color: "#1d3557", width: 2 } },
    },
  ],
  series: [
    {
      name: "游玩次数",
      type: "line",
      smooth: 0.38,
      showSymbol: false,
      symbolSize: 6,
      animationDuration: 1500,
      animationDelay: (index) => index * 22,
      lineStyle: { width: 3, color: "#06d6a0", shadowColor: "rgba(6,214,160,0.25)", shadowBlur: 8, shadowOffsetY: 4 },
      itemStyle: { color: "#06d6a0" },
      areaStyle: {
        color: {
          type: "linear", x: 0, y: 0, x2: 0, y2: 1,
          colorStops: [
            { offset: 0, color: "rgba(6,214,160,0.28)" },
            { offset: 1, color: "rgba(6,214,160,0.01)" },
          ],
        },
      },
      data: props.trend.map((item) => item.runs),
    },
    {
      name: "通关次数",
      type: "line",
      smooth: 0.38,
      showSymbol: false,
      animationDuration: 1250,
      lineStyle: { width: 2.4, color: "#ffd166" },
      itemStyle: { color: "#ffd166" },
      data: props.trend.map((item) => item.completed),
    },
    {
      name: "碰撞事件",
      type: "bar",
      barWidth: "34%",
      animationDuration: 1100,
      animationDelay: (index) => 140 + index * 26,
      itemStyle: {
        borderRadius: [5, 5, 0, 0],
        borderColor: "#1d3557",
        borderWidth: 1.5,
        color: {
          type: "linear", x: 0, y: 0, x2: 0, y2: 1,
          colorStops: [
            { offset: 0, color: "#ff8a8a" },
            { offset: 1, color: "#ff6b6b" },
          ],
        },
      },
      data: props.trend.map((item) => item.collisions),
    },
    {
      name: "通关率",
      type: "line",
      yAxisIndex: 1,
      smooth: 0.42,
      showSymbol: false,
      animationDuration: 1400,
      lineStyle: { width: 2, type: "dashed", color: "#63b3ed" },
      data: props.trend.map((item) => item.completion_rate),
    },
  ],
}));

useEChart(chartEl, option);
</script>

<template>
  <div ref="chartEl" class="trend-canvas" role="img" aria-label="游玩次数、通关率与碰撞事件趋势"></div>
</template>

<style scoped>
.trend-canvas { width: 100%; height: 320px; }
</style>
