<script setup>
defineProps({
  title: { type: String, required: true },
  eyebrow: { type: String, default: "" },
  hint: { type: String, default: "" },
  accent: { type: String, default: "#06d6a0" },
  empty: { type: Boolean, default: false },
  emptyText: { type: String, default: "等待第一批数据" },
  tall: { type: Boolean, default: false },
});
</script>

<template>
  <section class="chart-card" :class="{ tall }" :style="{ '--accent': accent }">
    <span class="card-tack tack-a" aria-hidden="true"></span>
    <span class="card-tack tack-b" aria-hidden="true"></span>
    <header class="chart-head">
      <div>
        <p v-if="eyebrow" class="chart-eyebrow">{{ eyebrow }}</p>
        <h2>{{ title }}</h2>
      </div>
      <div class="chart-actions">
        <slot name="actions" />
      </div>
    </header>
    <p v-if="hint" class="chart-hint">{{ hint }}</p>
    <div class="chart-body">
      <slot />
      <div v-if="empty" class="empty-state">
        <span class="empty-badge">🚡</span>
        <strong>还没有轨迹</strong>
        <p>{{ emptyText }}</p>
      </div>
    </div>
    <footer v-if="$slots.footer" class="chart-footer">
      <slot name="footer" />
    </footer>
  </section>
</template>

<style scoped>
.chart-card {
  position: relative;
  display: flex;
  flex-direction: column;
  min-width: 0;
  padding: 20px 20px 15px;
  border: var(--border);
  border-radius: 24px;
  background: var(--cream);
  box-shadow: var(--shadow-card);
  color: var(--navy);
  overflow: hidden;
  transform: translateY(0) scale(1);
  transition: transform 0.2s cubic-bezier(0.34, 1.56, 0.64, 1), box-shadow 0.2s ease;
  animation: card-in 0.6s cubic-bezier(0.34, 1.56, 0.64, 1) both;
}
.chart-card:hover {
  transform: translateY(-3px) scale(1.004);
  box-shadow: 0 10px 0 var(--navy), 0 18px 30px rgba(29, 53, 87, 0.16);
}
.chart-card:active {
  transform: translateY(1px) scale(0.998);
  box-shadow: 0 4px 0 var(--navy), 0 8px 12px rgba(29, 53, 87, 0.1);
}
.chart-card::before {
  content: "";
  position: absolute;
  inset: 9px;
  border: 1.5px dashed rgba(29, 53, 87, 0.13);
  border-radius: 17px;
  pointer-events: none;
}
.chart-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
  position: relative;
  z-index: 1;
}
.chart-eyebrow {
  margin: 0 0 4px;
  color: var(--accent);
  font-family: var(--font-mono);
  font-size: 8px;
  font-weight: 700;
  letter-spacing: 0.14em;
  text-transform: uppercase;
}
.chart-head h2 {
  margin: 0;
  color: var(--navy);
  font-family: var(--font-display);
  font-size: clamp(16px, 1.25vw, 19px);
  font-weight: 900;
  letter-spacing: 0.01em;
}
.chart-actions {
  display: flex;
  align-items: center;
  gap: 8px;
  color: var(--muted);
  font-size: 10px;
}
.chart-hint {
  position: relative;
  z-index: 1;
  margin: 7px 0 0;
  color: var(--muted);
  font-family: var(--font-body);
  font-size: 10px;
  line-height: 1.55;
}
.chart-body {
  position: relative;
  flex: 1;
  min-height: 0;
  margin-top: 8px;
  z-index: 1;
}
.chart-footer {
  position: relative;
  z-index: 1;
  margin-top: 10px;
  padding-top: 10px;
  border-top: 2px dashed rgba(29, 53, 87, 0.14);
}
.card-tack {
  position: absolute;
  top: 10px;
  width: 8px;
  height: 8px;
  border: 1.5px solid rgba(29, 53, 87, 0.35);
  border-radius: 50%;
  background: var(--accent);
  opacity: 0.55;
}
.tack-a { right: 18px; }
.tack-b { right: 32px; background: var(--coral); }
.empty-state {
  position: absolute;
  inset: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 6px;
  color: var(--muted);
  text-align: center;
  background: rgba(255, 244, 210, 0.72);
  border-radius: 14px;
}
.empty-state strong { color: var(--navy); font-size: 13px; }
.empty-state p { margin: 0; font-size: 10px; }
.empty-badge {
  display: grid;
  place-items: center;
  width: 44px;
  height: 44px;
  margin-bottom: 3px;
  border: 2px solid var(--navy);
  border-radius: 14px;
  background: var(--mint-soft);
  box-shadow: 0 3px 0 var(--navy);
  font-size: 22px;
  animation: bob 2.6s ease-in-out infinite;
}
.tall { min-height: 520px; }
@keyframes card-in {
  from { opacity: 0; transform: translateY(26px) scale(0.98); }
  to { opacity: 1; transform: none; }
}
@keyframes bob { 50% { transform: translateY(-4px) rotate(-2deg); } }
</style>
