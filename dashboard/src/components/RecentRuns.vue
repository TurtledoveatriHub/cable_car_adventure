<script setup>
import { computed } from "vue";
import { duration, number, platform, relativeTime } from "../utils/format";

const props = defineProps({
  runs: { type: Array, default: () => [] },
  limit: { type: Number, default: 8 },
});
const rows = computed(() => props.runs.slice(0, props.limit));
</script>

<template>
  <div class="recent-list">
    <article
      v-for="(run, index) in rows"
      :key="`${run.level_id}-${run.received_at}-${index}`"
      class="run-row"
      :class="run.completed ? 'is-ok' : 'is-fail'"
      :style="{ '--i': index }"
    >
      <span class="run-platform" :style="{ '--pcolor': platform(run.platform).color }">
        {{ platform(run.platform).short }}
      </span>
      <div class="run-main">
        <strong>{{ run.level_name }}</strong>
        <small>
          <span v-if="run.custom" class="tag">UGC</span>
          {{ duration(run.time_seconds) }} · {{ number(run.passengers) }} 乘客
          <template v-if="run.collisions"> · 💥{{ run.collisions }}</template>
        </small>
      </div>
      <div class="run-result">
        <span>{{ run.completed ? "通关" : "失败" }}</span>
        <small v-if="run.completed">{{ "★".repeat(Math.max(0, Math.min(3, run.stars))) }}</small>
        <small v-else>{{ Math.round((run.progress || 0) * 100) }}%</small>
      </div>
      <time>{{ relativeTime(run.received_at) }}</time>
    </article>
    <div v-if="rows.length === 0" class="empty">还没有结算记录 🚡</div>
  </div>
</template>

<style scoped>
.recent-list { display: flex; flex-direction: column; gap: 6px; }
.run-row {
  display: grid;
  grid-template-columns: 39px minmax(0, 1fr) 43px 42px;
  gap: 7px;
  align-items: center;
  padding: 7px 8px;
  border: 2px solid var(--navy);
  border-radius: 12px;
  background: var(--paper);
  box-shadow: 0 2px 0 var(--navy);
  animation: run-in 0.48s cubic-bezier(0.34, 1.56, 0.64, 1) both;
  animation-delay: calc(var(--i) * 45ms);
  transition: transform 0.15s cubic-bezier(0.34, 1.56, 0.64, 1), background 0.15s;
}
.run-row:hover { transform: translateX(3px) rotate(0.3deg); background: #fffaf0; }
.run-row.is-ok { border-left: 7px solid var(--mint); }
.run-row.is-fail { border-left: 7px solid var(--coral); }
.run-platform {
  display: grid;
  place-items: center;
  height: 24px;
  border: 1.5px solid var(--navy);
  border-radius: 7px;
  color: var(--navy);
  background: color-mix(in srgb, var(--pcolor) 30%, #fff);
  font-size: 8px;
  font-weight: 800;
}
.run-main { min-width: 0; }
.run-main strong { display: block; color: var(--navy); font-size: 10px; font-weight: 700; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.run-main small { display: block; color: var(--muted); font-size: 8px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.tag { margin-right: 3px; padding: 0 4px; border-radius: 3px; background: var(--yellow-soft); color: var(--navy); font-size: 7px; font-weight: 700; }
.run-result { display: flex; flex-direction: column; gap: 1px; align-items: flex-start; font-size: 9px; font-weight: 700; }
.is-ok .run-result span { color: #05775b; }
.is-fail .run-result span { color: var(--coral); }
.run-result small { color: var(--navy); font-family: var(--font-mono); font-size: 8px; }
.run-row time { color: var(--muted); font-size: 7px; text-align: right; white-space: nowrap; }
.empty { padding: 30px 0; text-align: center; color: var(--muted); font-size: 10px; }
@keyframes run-in { from { opacity: 0; transform: translateY(9px); } to { opacity: 1; transform: none; } }
</style>
