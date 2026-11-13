<script setup>
import { computed } from "vue";
import { number, percent } from "../utils/format";

const props = defineProps({
  levels: { type: Array, default: () => [] },
  limit: { type: Number, default: 6 },
});

const rows = computed(() => props.levels.slice(0, props.limit));
const medals = ["🥇", "🥈", "🥉"];
</script>

<template>
  <div class="ugc-board">
    <div
      v-for="(item, index) in rows"
      :key="item.level_id"
      class="board-row"
      :class="`rank-${index + 1}`"
      :style="{ '--i': index, '--heat': `${Math.max(4, item.heat_score)}%` }"
    >
      <span class="medal" :class="{ emoji: index < 3 }">
        {{ index < 3 ? medals[index] : String(index + 1).padStart(2, "0") }}
      </span>
      <div class="board-main">
        <strong>{{ item.name }}</strong>
        <small>{{ item.author_name || "匿名作者" }} · {{ number(item.plays) }} 次游玩</small>
        <div class="heat-track"><i></i></div>
      </div>
      <span class="churn" :class="{ danger: item.churn_rate >= 55 }">
        <b>{{ percent(item.churn_rate, 0) }}</b>
        <small>劝退</small>
      </span>
    </div>
    <div v-if="rows.length === 0" class="table-empty">还没有 UGC 关卡数据</div>
  </div>
</template>

<style scoped>
.ugc-board { display: flex; flex-direction: column; gap: 8px; }
.board-row {
  position: relative;
  display: grid;
  grid-template-columns: 33px minmax(0, 1fr) 44px;
  gap: 9px;
  align-items: center;
  padding: 8px 9px;
  border: 2px solid var(--navy);
  border-radius: 14px;
  background: var(--paper);
  box-shadow: 0 3px 0 var(--navy);
  animation: row-in 0.5s cubic-bezier(0.34, 1.56, 0.64, 1) both;
  animation-delay: calc(var(--i) * 55ms);
  transition: transform 0.16s cubic-bezier(0.34, 1.56, 0.64, 1), box-shadow 0.16s;
}
.board-row:hover { transform: translate(-2px, -3px) rotate(-0.4deg); box-shadow: 0 6px 0 var(--navy); }
.board-row.rank-1 { background: linear-gradient(100deg, var(--yellow-soft), var(--paper) 55%); }
.board-row.rank-2 { background: linear-gradient(100deg, #eef2f7, var(--paper) 55%); }
.board-row.rank-3 { background: linear-gradient(100deg, #ffe9d7, var(--paper) 55%); }
.medal {
  display: grid;
  place-items: center;
  width: 31px;
  height: 31px;
  border: 2px solid var(--navy);
  border-radius: 10px;
  background: var(--cream);
  color: var(--navy);
  font-family: var(--font-mono);
  font-size: 10px;
  font-weight: 800;
  box-shadow: 0 2px 0 var(--navy);
}
.medal.emoji { font-family: var(--font-body); font-size: 21px; border: 0; box-shadow: none; background: transparent; }
.board-main { min-width: 0; }
.board-main strong {
  display: block;
  color: var(--navy);
  font-family: var(--font-display);
  font-size: 11px;
  font-weight: 900;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.board-main small { display: block; color: var(--muted); font-size: 8px; }
.heat-track {
  height: 5px;
  margin-top: 5px;
  border: 1.5px solid var(--navy);
  border-radius: 999px;
  background: var(--cream);
  overflow: hidden;
}
.heat-track i {
  display: block;
  width: var(--heat);
  height: 100%;
  border-radius: inherit;
  background: linear-gradient(90deg, var(--mint), var(--yellow) 58%, var(--coral));
  animation: grow 0.9s cubic-bezier(0.34, 1.56, 0.64, 1) both;
  animation-delay: calc(160ms + var(--i) * 55ms);
}
.churn {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  color: var(--navy);
  line-height: 1.05;
}
.churn b { font-family: var(--font-mono); font-size: 10px; }
.churn small { color: var(--muted); font-size: 7px; }
.churn.danger b { color: var(--coral); }
.table-empty { padding: 26px 0; text-align: center; color: var(--muted); font-size: 10px; }
@keyframes row-in { from { opacity: 0; transform: translateX(-16px) scale(0.97); } to { opacity: 1; transform: none; } }
@keyframes grow { from { width: 0; } to { width: var(--heat); } }
</style>
