<script setup>
import { number, percent } from "../utils/format";

defineProps({
  levels: { type: Array, default: () => [] },
});
const medals = ["🥇", "🥈", "🥉"];
</script>

<template>
  <div class="choke-list">
    <div
      v-for="(item, index) in levels"
      :key="item.level_id"
      class="choke-row"
      :style="{ '--i': index }"
    >
      <span class="choke-rank" :class="{ emoji: index < 3 }">{{ index < 3 ? medals[index] : index + 1 }}</span>
      <span class="choke-name">
        <strong>{{ item.name }}</strong>
        <small><i :class="{ ugc: item.custom }">{{ item.custom ? "UGC" : "主线" }}</i> 失败 {{ number(item.failed) }} · 碰撞 {{ number(item.collisions) }}</small>
      </span>
      <span class="choke-rate" :class="{ bad: item.completion_rate < 50 }">{{ percent(item.completion_rate, 0) }}</span>
    </div>
    <div v-if="levels.length === 0" class="empty">暂未发现明显卡点 🎉</div>
  </div>
</template>

<style scoped>
.choke-list { display: flex; flex-direction: column; gap: 7px; }
.choke-row {
  display: grid;
  grid-template-columns: 31px minmax(0, 1fr) 40px;
  gap: 8px;
  align-items: center;
  padding: 7px 8px;
  border: 2px solid var(--navy);
  border-radius: 13px;
  background: var(--paper);
  box-shadow: 0 3px 0 var(--navy);
  animation: row-in 0.48s cubic-bezier(0.34, 1.56, 0.64, 1) both;
  animation-delay: calc(var(--i) * 55ms);
  transition: transform 0.16s cubic-bezier(0.34, 1.56, 0.64, 1), box-shadow 0.16s;
}
.choke-row:hover { transform: translateY(-2px); box-shadow: 0 5px 0 var(--navy); }
.choke-rank {
  display: grid;
  place-items: center;
  width: 29px;
  height: 29px;
  border: 2px solid var(--navy);
  border-radius: 9px;
  background: var(--cream);
  color: var(--navy);
  font-family: var(--font-mono);
  font-size: 9px;
  font-weight: 800;
  box-shadow: 0 2px 0 var(--navy);
}
.choke-rank.emoji { border: 0; box-shadow: none; background: transparent; font-family: var(--font-body); font-size: 20px; }
.choke-name { min-width: 0; }
.choke-name strong {
  display: block;
  color: var(--navy);
  font-family: var(--font-display);
  font-size: 10px;
  font-weight: 900;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.choke-name small { display: block; color: var(--muted); font-size: 8px; }
.choke-name i {
  padding: 0 4px;
  border-radius: 4px;
  background: var(--yellow-soft);
  color: var(--navy);
  font-style: normal;
  font-size: 7px;
  font-weight: 700;
}
.choke-name i.ugc { background: var(--coral-soft); }
.choke-rate {
  color: var(--navy);
  font-family: var(--font-mono);
  font-size: 9px;
  font-weight: 800;
  text-align: right;
}
.choke-rate.bad { color: var(--coral); }
.empty { padding: 30px 0; text-align: center; color: var(--muted); font-size: 10px; }
@keyframes row-in { from { opacity: 0; transform: translateX(-12px); } to { opacity: 1; transform: none; } }
</style>
