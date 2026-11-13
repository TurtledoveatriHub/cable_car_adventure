<script setup>
import { computed } from "vue";
import { relativeTime } from "../utils/format";

const props = defineProps({
  days: { type: Number, required: true },
  loading: { type: Boolean, default: false },
  updatedAt: { type: String, default: "" },
  live: { type: Boolean, default: true },
});
const emit = defineEmits(["update:days", "refresh"]);

const updatedText = computed(() => (props.updatedAt ? relativeTime(props.updatedAt) : "等待数据"));
const ranges = [
  { value: 7, label: "7 天" },
  { value: 30, label: "30 天" },
  { value: 90, label: "90 天" },
];
</script>

<template>
  <header class="topbar">
    <div class="brand">
      <div class="brand-mark" aria-hidden="true">
        <span class="wire"></span>
        <span class="cabin"><i></i><i></i></span>
        <span class="sun"></span>
      </div>
      <div class="brand-copy">
        <p class="brand-kicker">CABLE CAR ADVENTURE</p>
        <h1>缆车大冒险 <span>数据总控台</span></h1>
      </div>
    </div>

    <div class="topbar-actions">
      <div class="live-pill" :class="{ 'is-loading': loading }">
        <span class="live-dot"></span>
        <span>{{ loading ? "同步中" : live ? "实时数据" : "已暂停" }}</span>
        <em>{{ updatedText }}</em>
      </div>

      <div class="range-switch" role="group" aria-label="时间范围">
        <button
          v-for="item in ranges"
          :key="item.value"
          class="range-chip"
          :class="{ active: days === item.value }"
          type="button"
          @click="emit('update:days', item.value)"
        >
          {{ item.label }}
        </button>
      </div>

      <button class="refresh-btn" type="button" :disabled="loading" @click="emit('refresh')" aria-label="刷新看板">
        <svg viewBox="0 0 24 24" width="19" height="19" aria-hidden="true">
          <path
            d="M20 11a8.1 8.1 0 0 0-15.5-2M4 4v5h5M4 13a8.1 8.1 0 0 0 15.5 2M20 20v-5h-5"
            fill="none"
            stroke="currentColor"
            stroke-width="2.2"
            stroke-linecap="round"
            stroke-linejoin="round"
          />
        </svg>
      </button>
    </div>
  </header>
</template>

<style scoped>
.topbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 24px;
  padding: 4px 2px 24px;
}
.brand { display: flex; align-items: center; gap: 14px; min-width: 0; }
.brand-mark {
  position: relative;
  width: 62px;
  height: 62px;
  flex: 0 0 62px;
  border: var(--border);
  border-radius: 20px;
  background: var(--cream);
  box-shadow: 0 5px 0 var(--navy);
  transform: rotate(-3deg);
  transition: transform 0.2s cubic-bezier(0.34, 1.56, 0.64, 1);
}
.brand:hover .brand-mark { transform: rotate(2deg) translateY(-2px); }
.wire {
  position: absolute;
  left: 10px;
  right: 10px;
  top: 22px;
  height: 2px;
  border-radius: 2px;
  background: var(--navy);
  transform: rotate(-10deg);
}
.cabin {
  position: absolute;
  left: 23px;
  top: 28px;
  width: 19px;
  height: 17px;
  border: 2px solid var(--navy);
  border-radius: 4px 4px 8px 8px;
  background: var(--coral);
  box-shadow: inset 0 -5px 0 rgba(255, 255, 255, 0.22);
  animation: cabin-bob 2.8s ease-in-out infinite;
}
.cabin::before {
  content: "";
  position: absolute;
  left: 8px;
  top: -8px;
  width: 2px;
  height: 7px;
  background: var(--navy);
}
.cabin i {
  position: absolute;
  top: 4px;
  width: 3px;
  height: 5px;
  border-radius: 1px;
  background: var(--cream);
}
.cabin i:first-child { left: 4px; }
.cabin i:last-child { left: 10px; }
.sun {
  position: absolute;
  right: 8px;
  top: 8px;
  width: 10px;
  height: 10px;
  border: 2px solid var(--navy);
  border-radius: 50%;
  background: var(--yellow);
}
.brand-copy { min-width: 0; }
.brand-kicker {
  margin: 0 0 3px;
  color: var(--navy-soft);
  font-family: var(--font-mono);
  font-size: 9px;
  font-weight: 700;
  letter-spacing: 0.16em;
}
.brand-copy h1 {
  margin: 0;
  color: var(--navy);
  font-family: var(--font-display);
  font-size: clamp(24px, 2.6vw, 34px);
  font-weight: 900;
  line-height: 1.06;
  letter-spacing: 0.01em;
  text-shadow: 0 2px 0 rgba(255, 255, 255, 0.55);
  white-space: nowrap;
}
.brand-copy h1 span { color: var(--coral); }

.topbar-actions { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; justify-content: flex-end; }
.live-pill {
  display: flex;
  align-items: center;
  gap: 7px;
  height: 38px;
  padding: 0 12px;
  border: 2px solid var(--navy);
  border-radius: 999px;
  background: var(--mint-soft);
  box-shadow: 0 3px 0 var(--navy);
  color: var(--navy);
  font-size: 11px;
  font-weight: 700;
}
.live-pill em { color: var(--navy-soft); font-style: normal; font-family: var(--font-mono); font-size: 9px; }
.live-dot {
  width: 8px;
  height: 8px;
  border: 1.5px solid var(--navy);
  border-radius: 50%;
  background: var(--mint);
  animation: pulse 1.8s ease-in-out infinite;
}
.is-loading .live-dot { background: var(--yellow); animation-duration: 0.7s; }

.range-switch {
  display: flex;
  padding: 3px;
  border: 2px solid var(--navy);
  border-radius: 14px;
  background: var(--cream);
  box-shadow: 0 3px 0 var(--navy);
}
.range-chip {
  border: 0;
  border-radius: 9px;
  padding: 7px 11px;
  background: transparent;
  color: var(--navy-soft);
  font-family: var(--font-display);
  font-size: 11px;
  font-weight: 700;
  cursor: pointer;
  transition: transform 0.15s cubic-bezier(0.34, 1.56, 0.64, 1), background 0.15s;
}
.range-chip:hover { background: var(--yellow-soft); transform: translateY(-1px); }
.range-chip.active {
  background: var(--coral);
  color: #fff;
  box-shadow: inset 0 -2px 0 rgba(0, 0, 0, 0.15);
}
.refresh-btn {
  display: grid;
  place-items: center;
  width: 40px;
  height: 40px;
  border: 2px solid var(--navy);
  border-radius: 13px;
  background: var(--yellow);
  box-shadow: 0 3px 0 var(--navy);
  color: var(--navy);
  cursor: pointer;
  transition: transform 0.15s cubic-bezier(0.34, 1.56, 0.64, 1), box-shadow 0.15s;
}
.refresh-btn:hover { transform: translateY(-2px) rotate(8deg); box-shadow: 0 5px 0 var(--navy); }
.refresh-btn:active { transform: translateY(2px); box-shadow: 0 1px 0 var(--navy); }
.refresh-btn:disabled { opacity: 0.55; cursor: wait; }
.refresh-btn:disabled svg { animation: spin 0.9s linear infinite; }

@keyframes pulse { 50% { transform: scale(0.72); opacity: 0.55; } }
@keyframes cabin-bob { 50% { transform: translateY(-3px) rotate(2deg); } }
@keyframes spin { to { transform: rotate(360deg); } }
@media (max-width: 980px) {
  .topbar { align-items: flex-start; flex-direction: column; }
  .topbar-actions { width: 100%; justify-content: flex-start; }
  .brand-copy h1 { white-space: normal; }
}
@media (max-width: 560px) {
  .live-pill em { display: none; }
  .brand-mark { width: 52px; height: 52px; flex-basis: 52px; border-radius: 16px; }
  .cabin { left: 19px; top: 24px; }
  .wire { top: 18px; }
  .sun { right: 6px; top: 6px; }
  .range-chip { padding: 7px 9px; }
}
</style>
