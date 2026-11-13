<script setup>
import { computed, toRef } from "vue";
import { useCountUp } from "../composables/useCountUp";
import { deltaTone, signedPercent } from "../utils/format";

const props = defineProps({
  label: { type: String, required: true },
  value: { type: Number, default: 0 },
  formatter: { type: Function, default: (value) => Math.round(value).toLocaleString("zh-CN") },
  delta: { type: Number, default: null },
  inverseDelta: { type: Boolean, default: false },
  hint: { type: String, default: "" },
  icon: { type: String, default: "✦" },
  accent: { type: String, default: "#06d6a0" },
  soft: { type: String, default: "#d9fff5" },
  spark: { type: Array, default: () => [] },
  suffix: { type: String, default: "" },
});

const source = toRef(props, "value");
const { display } = useCountUp(source);
const text = computed(() => props.formatter(display.value));
const tone = computed(() => (props.delta === null ? "flat" : deltaTone(props.delta, props.inverseDelta)));
const deltaText = computed(() => (props.delta === null ? "" : signedPercent(props.delta)));

const sparkPoints = computed(() => {
  const values = props.spark.map((item) => Number(item) || 0);
  if (values.length < 2) return "";
  const max = Math.max(1, ...values);
  const min = Math.min(...values, 0);
  return values
    .map((value, index) => {
      const x = (index / (values.length - 1)) * 100;
      const y = 30 - ((value - min) / Math.max(1, max - min)) * 24;
      return `${x.toFixed(1)},${y.toFixed(1)}`;
    })
    .join(" ");
});
</script>

<template>
  <article class="kpi-card" :style="{ '--accent': accent, '--soft': soft }">
    <div class="kpi-badge" aria-hidden="true">
      <span>{{ icon }}</span>
      <i></i>
    </div>
    <div class="kpi-copy">
      <div class="kpi-head">
        <span class="kpi-label">{{ label }}</span>
        <span v-if="delta !== null" class="kpi-delta" :class="tone">
          {{ tone === "up" ? "↑" : tone === "down" ? "↓" : "•" }} {{ deltaText }}
        </span>
      </div>
      <div class="kpi-value-row">
        <strong class="kpi-value">{{ text }}<small v-if="suffix">{{ suffix }}</small></strong>
      </div>
      <p class="kpi-hint">{{ hint }}</p>
    </div>
    <svg v-if="sparkPoints" class="kpi-spark" viewBox="0 0 100 34" preserveAspectRatio="none" aria-hidden="true">
      <polyline :points="sparkPoints" fill="none" :stroke="accent" stroke-width="2.4" stroke-linejoin="round" stroke-linecap="round" />
    </svg>
    <span class="kpi-stitch"></span>
  </article>
</template>

<style scoped>
.kpi-card {
  position: relative;
  display: flex;
  align-items: center;
  gap: 13px;
  min-height: 126px;
  padding: 17px 16px 14px;
  border: var(--border);
  border-radius: 22px;
  background:
    radial-gradient(circle at 102% -10%, var(--soft), transparent 44%),
    var(--cream);
  box-shadow: var(--shadow-card);
  transform: translateY(0) scale(1);
  transition: transform 0.18s cubic-bezier(0.34, 1.56, 0.64, 1), box-shadow 0.18s ease;
  overflow: hidden;
}
.kpi-card:hover {
  transform: translateY(-4px) scale(1.02);
  box-shadow: 0 11px 0 var(--navy), 0 18px 26px rgba(29, 53, 87, 0.17);
}
.kpi-card:active {
  transform: translateY(2px) scale(0.995);
  box-shadow: 0 3px 0 var(--navy), 0 6px 10px rgba(29, 53, 87, 0.12);
  transition-duration: 0.08s;
}
.kpi-badge {
  position: relative;
  display: grid;
  place-items: center;
  width: 58px;
  height: 58px;
  flex: 0 0 58px;
  border: 2.5px solid var(--navy);
  border-radius: 18px;
  background: var(--soft);
  box-shadow: 0 4px 0 var(--navy);
  color: var(--navy);
  font-family: var(--font-display);
  font-size: 25px;
  line-height: 1;
  transform: rotate(-3deg);
}
.kpi-badge i {
  position: absolute;
  right: 6px;
  top: 6px;
  width: 7px;
  height: 7px;
  border: 1.5px solid var(--navy);
  border-radius: 50%;
  background: var(--accent);
}
.kpi-copy { position: relative; flex: 1; min-width: 0; z-index: 1; }
.kpi-head { display: flex; align-items: center; gap: 6px; }
.kpi-label {
  color: var(--navy);
  font-size: 12px;
  font-weight: 700;
  letter-spacing: 0.03em;
  white-space: nowrap;
}
.kpi-delta {
  margin-left: auto;
  padding: 2px 6px;
  border: 1.5px solid var(--navy);
  border-radius: 999px;
  font-family: var(--font-mono);
  font-size: 8px;
  font-weight: 700;
  white-space: nowrap;
  background: var(--paper);
}
.kpi-delta.up { background: var(--mint-soft); color: #05775b; }
.kpi-delta.down { background: var(--coral-soft); color: #b63d3d; }
.kpi-delta.flat { background: var(--yellow-soft); color: var(--navy); }
.kpi-value-row { display: flex; align-items: flex-end; margin-top: 7px; }
.kpi-value {
  color: var(--navy);
  font-family: var(--font-display);
  font-size: clamp(30px, 2.35vw, 41px);
  font-weight: 900;
  line-height: 0.92;
  letter-spacing: -0.035em;
  font-variant-numeric: tabular-nums;
  text-shadow: 0 2px 0 rgba(255, 255, 255, 0.65);
}
.kpi-value small { margin-left: 3px; font-size: 14px; font-weight: 700; color: var(--navy-soft); }
.kpi-hint {
  margin: 7px 0 0;
  color: var(--muted);
  font-family: var(--font-body);
  font-size: 9px;
  line-height: 1.4;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.kpi-spark {
  position: absolute;
  right: 13px;
  bottom: 9px;
  width: 66px;
  height: 27px;
  opacity: 0.5;
  z-index: 0;
  overflow: visible;
}
.kpi-stitch {
  position: absolute;
  left: 19px;
  right: 19px;
  bottom: 7px;
  height: 2px;
  border-radius: 2px;
  background: repeating-linear-gradient(90deg, rgba(29, 53, 87, 0.16) 0 5px, transparent 5px 10px);
}
@media (max-width: 1200px) {
  .kpi-card { min-height: 116px; padding: 14px 13px 12px; gap: 10px; }
  .kpi-badge { width: 48px; height: 48px; flex-basis: 48px; font-size: 20px; border-radius: 15px; }
  .kpi-value { font-size: 29px; }
  .kpi-spark { width: 52px; }
}
</style>
