<script setup>
import { computed, ref } from "vue";
import { useEChart } from "../composables/useEChart";
import { duration, number, percent, platform } from "../utils/format";

const props = defineProps({
  platforms: { type: Array, default: () => [] },
});

const chartEl = ref(null);
const totalRuns = computed(() => props.platforms.reduce((sum, item) => sum + item.runs, 0));

const option = computed(() => ({
  animation: true,
  animationDuration: 1100,
  animationEasing: "elasticOut",
  animationType: "scale",
  tooltip: {
    trigger: "item",
    backgroundColor: "#fffdf3",
    borderColor: "#1d3557",
    borderWidth: 2,
    textStyle: { color: "#1d3557", fontSize: 11, fontWeight: 600 },
    formatter: (params) => `${params.name}<br/><b>${number(params.value)}</b> 次 · ${params.percent}%`,
  },
  series: [
    {
      type: "pie",
      radius: ["62%", "83%"],
      center: ["50%", "50%"],
      startAngle: 90,
      animationDuration: 1100,
      animationEasing: "elasticOut",
      animationType: "scale",
      itemStyle: { borderColor: "#1d3557", borderWidth: 3, borderRadius: 8 },
      label: { show: false },
      emphasis: {
        scale: true,
        scaleSize: 7,
        itemStyle: { shadowBlur: 18, shadowColor: "rgba(29,53,87,0.22)" },
      },
      data: props.platforms.map((item) => ({
        name: platform(item.id).short,
        value: item.runs,
        itemStyle: { color: platform(item.id).color },
      })),
    },
  ],
}));

useEChart(chartEl, option);
</script>

<template>
  <div class="platform-panel">
    <div class="donut-wrap">
      <div ref="chartEl" class="platform-donut" role="img" aria-label="三端游玩次数占比"></div>
      <div class="donut-center" aria-hidden="true">
        <span class="cart-emoji">🚡</span>
        <strong>{{ number(totalRuns) }}</strong>
        <small>总游玩</small>
      </div>
    </div>
    <div class="platform-rows">
      <div v-for="item in platforms" :key="item.id" class="platform-row">
        <span class="platform-badge" :style="{ '--pcolor': platform(item.id).color }">
          <i>{{ platform(item.id).glyph }}</i>
          {{ platform(item.id).label }}
        </span>
        <div class="platform-metrics">
          <strong>{{ number(item.runs) }}<small> 次</small></strong>
          <span>{{ percent(item.completion_rate) }} 通关</span>
          <span>{{ item.players }} 位玩家</span>
          <span>{{ duration(item.avg_time) }}</span>
        </div>
        <div class="platform-bar">
          <i :style="{ width: `${Math.max(2, item.share)}%`, background: platform(item.id).color }"></i>
        </div>
      </div>
      <div v-if="platforms.length === 0" class="platform-empty">还没有三端数据</div>
    </div>
  </div>
</template>

<style scoped>
.platform-panel {
  display: grid;
  grid-template-columns: 172px minmax(0, 1fr);
  gap: 12px;
  align-items: center;
  min-height: 238px;
}
.donut-wrap { position: relative; width: 172px; height: 190px; }
.platform-donut { width: 100%; height: 100%; }
.donut-center {
  position: absolute;
  inset: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  pointer-events: none;
}
.cart-emoji {
  font-size: 25px;
  line-height: 1;
  animation: cart-bob 2.5s ease-in-out infinite;
  filter: drop-shadow(0 2px 0 rgba(29, 53, 87, 0.18));
}
.donut-center strong {
  margin-top: 2px;
  color: var(--navy);
  font-family: var(--font-display);
  font-size: 20px;
  font-weight: 900;
  line-height: 1;
}
.donut-center small { color: var(--muted); font-size: 8px; }
.platform-rows { display: flex; flex-direction: column; gap: 7px; min-width: 0; }
.platform-row {
  display: grid;
  grid-template-columns: 80px minmax(0, 1fr);
  gap: 3px 9px;
  align-items: center;
  padding: 7px 9px;
  border: 2px solid var(--navy);
  border-radius: 13px;
  background: var(--paper);
  box-shadow: 0 3px 0 var(--navy);
  transition: transform 0.16s cubic-bezier(0.34, 1.56, 0.64, 1), box-shadow 0.16s;
}
.platform-row:hover { transform: translateY(-2px); box-shadow: 0 5px 0 var(--navy); }
.platform-badge {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  color: var(--navy);
  font-size: 10px;
  font-weight: 700;
  white-space: nowrap;
}
.platform-badge i {
  display: grid;
  place-items: center;
  width: 19px;
  height: 19px;
  border: 1.5px solid var(--navy);
  border-radius: 6px;
  background: color-mix(in srgb, var(--pcolor) 38%, #fff);
  font-style: normal;
  font-size: 9px;
}
.platform-metrics {
  display: flex;
  align-items: baseline;
  gap: 7px;
  overflow: hidden;
  white-space: nowrap;
  color: var(--muted);
  font-size: 8px;
}
.platform-metrics strong {
  color: var(--navy);
  font-family: var(--font-display);
  font-size: 17px;
  font-weight: 900;
}
.platform-metrics strong small { color: var(--muted); font-size: 8px; font-weight: 400; }
.platform-bar {
  grid-column: 1 / -1;
  height: 5px;
  border: 1.5px solid var(--navy);
  border-radius: 999px;
  background: var(--mint-soft);
  overflow: hidden;
}
.platform-bar i { display: block; height: 100%; border-radius: inherit; }
.platform-empty { padding: 28px 0; text-align: center; color: var(--muted); font-size: 10px; }
@keyframes cart-bob { 50% { transform: translateY(-3px) rotate(-4deg); } }
@media (max-width: 640px) {
  .platform-panel { grid-template-columns: 1fr; }
  .donut-wrap { margin: 0 auto; }
  .platform-metrics span:nth-child(n + 3) { display: none; }
}
</style>
