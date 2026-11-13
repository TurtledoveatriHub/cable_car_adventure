<script setup>
import { computed, ref } from "vue";
import { useEChart } from "../composables/useEChart";
import { number, percent } from "../utils/format";

const props = defineProps({
  funnel: { type: Object, default: () => ({}) },
});

const chartEl = ref(null);
const values = computed(() => {
  const rawRuns = Number(props.funnel.runs) || 0;
  const enters = Math.max(Number(props.funnel.enters) || 0, rawRuns);
  const runs = Math.min(rawRuns, enters);
  const completed = Math.min(Number(props.funnel.completed) || 0, runs);
  return { enters, runs, completed };
});

const option = computed(() => ({
  animation: true,
  animationDuration: 1100,
  animationEasing: "cubicOut",
  color: ["#06d6a0", "#ffd166", "#ff6b6b"],
  tooltip: {
    trigger: "item",
    backgroundColor: "#fffdf3",
    borderColor: "#1d3557",
    borderWidth: 2,
    textStyle: { color: "#1d3557", fontSize: 10, fontWeight: 600 },
    formatter: (params) => `${params.name}<br/><b>${number(params.value)}</b> 次`,
  },
  series: [
    {
      type: "funnel",
      top: 8,
      bottom: 4,
      left: "6%",
      width: "88%",
      sort: "descending",
      minSize: "22%",
      maxSize: "100%",
      gap: 4,
      label: {
        show: true,
        position: "inside",
        color: "#1d3557",
        fontSize: 10,
        fontWeight: 800,
        formatter: (params) => `${params.name}  ${number(params.value)}`,
      },
      labelLine: { show: false },
      itemStyle: { borderColor: "#1d3557", borderWidth: 2, borderRadius: 7 },
      emphasis: { label: { fontSize: 11 } },
      data: [
        { name: "进入 UGC", value: values.value.enters },
        { name: "开始游玩", value: values.value.runs },
        { name: "完成关卡", value: values.value.completed },
      ],
    },
  ],
}));

useEChart(chartEl, option);
</script>

<template>
  <div class="funnel-wrap">
    <div ref="chartEl" class="funnel-canvas" role="img" aria-label="UGC 进入、游玩、完成漏斗"></div>
    <div class="funnel-stats">
      <div><span>进入→游玩</span><strong>{{ percent(funnel.enter_to_run_rate) }}</strong></div>
      <div><span>游玩→通关</span><strong>{{ percent(funnel.completion_rate) }}</strong></div>
      <div><span>整体劝退</span><strong class="warn">{{ percent(funnel.churn_rate) }}</strong></div>
    </div>
    <div class="funnel-social">
      <span>♥ {{ number(funnel.likes) }} 点赞</span>
      <span>★ {{ number(funnel.favorites) }} 收藏</span>
      <span>▷ {{ number(funnel.plays) }} 次开始</span>
    </div>
  </div>
</template>

<style scoped>
.funnel-wrap { padding-top: 2px; }
.funnel-canvas { width: 100%; height: 178px; }
.funnel-stats { display: grid; grid-template-columns: repeat(3, 1fr); gap: 7px; margin-top: 8px; }
.funnel-stats div {
  padding: 8px 7px;
  border: 2px solid var(--navy);
  border-radius: 11px;
  background: var(--paper);
  box-shadow: 0 2px 0 var(--navy);
}
.funnel-stats span { display: block; color: var(--muted); font-size: 8px; }
.funnel-stats strong { display: block; margin-top: 2px; color: var(--navy); font-family: var(--font-mono); font-size: 12px; font-weight: 800; }
.funnel-stats strong.warn { color: var(--coral); }
.funnel-social { display: flex; flex-wrap: wrap; gap: 10px; margin-top: 8px; color: var(--navy-soft); font-size: 8px; font-weight: 600; }
</style>
