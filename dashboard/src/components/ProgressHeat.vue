<script setup>
import { computed, ref } from "vue";
import { useEChart } from "../composables/useEChart";
import { number } from "../utils/format";

const props = defineProps({
  bins: { type: Array, default: () => [] },
});

const chartEl = ref(null);
const peak = computed(() => {
  const sorted = [...props.bins].sort((a, b) => (b.collisions + b.failures) - (a.collisions + a.failures));
  return sorted[0] || null;
});

const option = computed(() => ({
  animation: true,
  animationDuration: 1100,
  animationEasing: "cubicOut",
  grid: { left: 34, right: 12, top: 34, bottom: 32 },
  legend: {
    top: 0,
    right: 0,
    itemWidth: 10,
    itemHeight: 7,
    itemGap: 14,
    icon: "roundRect",
    textStyle: { color: "#345473", fontSize: 9, fontWeight: 600 },
  },
  tooltip: {
    trigger: "axis",
    axisPointer: { type: "shadow", shadowStyle: { color: "rgba(29,53,87,0.06)" } },
    backgroundColor: "#fffdf3",
    borderColor: "#1d3557",
    borderWidth: 2,
    textStyle: { color: "#1d3557", fontSize: 10, fontWeight: 600 },
    formatter(params) {
      const row = params?.[0];
      const index = row?.dataIndex ?? 0;
      const bin = props.bins[index] || {};
      return `<b>${bin.label || ""} 进度段</b><br/>碰撞 <b style="color:#ff6b6b">${number(bin.collisions)}</b><br/>失败 <b style="color:#c48a00">${number(bin.failures)}</b>`;
    },
  },
  xAxis: {
    type: "category",
    data: props.bins.map((item) => item.label),
    axisLine: { lineStyle: { color: "#1d3557", width: 2 } },
    axisTick: { show: false },
    axisLabel: {
      color: "#5c7288",
      fontSize: 8,
      interval: (index) => index % 4 === 0,
    },
  },
  yAxis: {
    type: "value",
    minInterval: 1,
    splitLine: { lineStyle: { color: "rgba(29,53,87,0.12)", type: "dashed" } },
    axisLabel: { color: "#5c7288", fontSize: 8 },
    axisLine: { show: true, lineStyle: { color: "#1d3557", width: 2 } },
  },
  series: [
    {
      name: "碰撞事件",
      type: "bar",
      barWidth: "46%",
      animationDelay: (index) => index * 22,
      itemStyle: {
        borderRadius: [4, 4, 0, 0],
        borderColor: "#1d3557",
        borderWidth: 1.2,
        color: {
          type: "linear", x: 0, y: 0, x2: 0, y2: 1,
          colorStops: [{ offset: 0, color: "#ff8a8a" }, { offset: 1, color: "#ff6b6b" }],
        },
      },
      data: props.bins.map((item) => item.collisions),
    },
    {
      name: "失败结算",
      type: "bar",
      barWidth: "46%",
      animationDelay: (index) => 80 + index * 22,
      itemStyle: {
        borderRadius: [4, 4, 0, 0],
        borderColor: "#1d3557",
        borderWidth: 1.2,
        color: {
          type: "linear", x: 0, y: 0, x2: 0, y2: 1,
          colorStops: [{ offset: 0, color: "#ffe08a" }, { offset: 1, color: "#ffd166" }],
        },
      },
      data: props.bins.map((item) => item.failures),
    },
  ],
}));

useEChart(chartEl, option);
</script>

<template>
  <div>
    <div class="heat-meta">
      <span class="heat-chip" v-if="peak">
        <i></i> 峰值卡点 {{ peak.label }}
      </span>
      <span class="heat-note">横轴为关卡进度，越靠右越接近终点</span>
    </div>
    <div ref="chartEl" class="heat-canvas" role="img" aria-label="玩家卡点分布：按关卡进度统计碰撞与失败"></div>
  </div>
</template>

<style scoped>
.heat-meta { display: flex; align-items: center; justify-content: space-between; gap: 10px; margin: 2px 0 0; }
.heat-chip {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 4px 9px;
  border: 2px solid var(--navy);
  border-radius: 999px;
  background: var(--coral-soft);
  box-shadow: 0 2px 0 var(--navy);
  color: var(--navy);
  font-size: 9px;
  font-weight: 700;
}
.heat-chip i {
  width: 7px;
  height: 7px;
  border: 1.5px solid var(--navy);
  border-radius: 50%;
  background: var(--coral);
}
.heat-note { color: var(--muted); font-size: 8px; text-align: right; }
.heat-canvas { width: 100%; height: 236px; }
</style>
