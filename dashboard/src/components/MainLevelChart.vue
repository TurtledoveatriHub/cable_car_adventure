<script setup>
import { computed, ref } from "vue";
import { useEChart } from "../composables/useEChart";
import { duration, levelDisplayName, number, percent } from "../utils/format";

const props = defineProps({
  levels: { type: Array, default: () => [] },
});

const chartEl = ref(null);
const sorted = computed(() => [...props.levels].sort((a, b) => b.runs - a.runs));
const visibleCount = 12;
const zoomEnd = computed(() => Math.min(100, (visibleCount / Math.max(1, sorted.value.length)) * 100));

function barColor(value) {
  if (value >= 70) return ["#06d6a0", "#4fe3bd"];
  if (value >= 40) return ["#ffd166", "#ffe08a"];
  return ["#ff6b6b", "#ff9a8e"];
}

const option = computed(() => {
  const rows = [...sorted.value].reverse();
  return {
    animation: true,
    animationDuration: 1100,
    animationEasing: "cubicOut",
    grid: { left: 106, right: 56, top: 18, bottom: 26 },
    tooltip: {
      trigger: "axis",
      axisPointer: { type: "shadow", shadowStyle: { color: "rgba(29,53,87,0.06)" } },
      backgroundColor: "#fffdf3",
      borderColor: "#1d3557",
      borderWidth: 2,
      textStyle: { color: "#1d3557", fontSize: 10, fontWeight: 600 },
      formatter(params) {
        const index = params?.[0]?.dataIndex ?? 0;
        const level = rows[index] || {};
        return `<b>${levelDisplayName(level)}</b><br/>游玩 <b>${number(level.runs)}</b> 次<br/>通关率 <b style="color:#c48a00">${percent(level.completion_rate)}</b><br/>平均用时 ${duration(level.avg_time)}<br/>碰撞 ${number(level.collisions)} 次`;
      },
    },
    dataZoom: [
      {
        type: "inside",
        yAxisIndex: 0,
        start: Math.max(0, 100 - zoomEnd.value),
        end: 100,
        zoomOnMouseWheel: true,
        moveOnMouseWheel: true,
        preventDefaultMouseMove: true,
      },
    ],
    xAxis: {
      type: "value",
      min: 0,
      max: 100,
      splitLine: { lineStyle: { color: "rgba(29,53,87,0.12)", type: "dashed" } },
      axisLabel: { color: "#5c7288", fontSize: 8, formatter: "{value}%" },
      axisLine: { show: true, lineStyle: { color: "#1d3557", width: 2 } },
    },
    yAxis: {
      type: "category",
      data: rows.map((item) => levelDisplayName(item)),
      axisLine: { show: true, lineStyle: { color: "#1d3557", width: 2 } },
      axisTick: { show: false },
      axisLabel: {
        color: "#1d3557",
        fontSize: 9,
        fontWeight: 600,
        width: 98,
        overflow: "truncate",
        formatter: (value) => (value.length > 9 ? `${value.slice(0, 9)}…` : value),
      },
    },
    series: [
      {
        type: "bar",
        barWidth: 11,
        showBackground: true,
        backgroundStyle: { color: "rgba(29,53,87,0.08)", borderRadius: 7 },
        animationDelay: (index) => index * 28,
        itemStyle: {
          borderRadius: [0, 7, 7, 0],
          borderColor: "#1d3557",
          borderWidth: 1.5,
          color: (params) => {
            const level = rows[params.dataIndex] || {};
            const [from, to] = barColor(Number(level.completion_rate) || 0);
            return {
              type: "linear", x: 0, y: 0, x2: 1, y2: 0,
              colorStops: [{ offset: 0, color: to }, { offset: 1, color: from }],
            };
          },
        },
        label: {
          show: true,
          position: "right",
          distance: 7,
          color: "#1d3557",
          fontFamily: "monospace",
          fontSize: 8,
          fontWeight: 700,
          formatter: (params) => `${Number(params.value).toFixed(1)}%`,
        },
        data: rows.map((item) => Number(item.completion_rate) || 0),
      },
    ],
  };
});

useEChart(chartEl, option);
</script>

<template>
  <div class="level-chart-wrap">
    <div ref="chartEl" class="level-canvas" role="img" aria-label="主线关卡通关率排行"></div>
    <p class="scroll-hint" v-if="levels.length > 12">滚轮 / 触控上下滑动查看全部 {{ levels.length }} 关</p>
  </div>
</template>

<style scoped>
.level-chart-wrap { position: relative; }
.level-canvas { width: 100%; height: 366px; }
.scroll-hint {
  position: absolute;
  right: 4px;
  bottom: -2px;
  margin: 0;
  color: var(--muted);
  font-size: 8px;
}
</style>
