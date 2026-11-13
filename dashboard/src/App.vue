<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from "vue";
import AppHeader from "./components/AppHeader.vue";
import ChartCard from "./components/ChartCard.vue";
import ChokeList from "./components/ChokeList.vue";
import KpiCard from "./components/KpiCard.vue";
import MainLevelChart from "./components/MainLevelChart.vue";
import PlatformPanel from "./components/PlatformPanel.vue";
import ProgressHeat from "./components/ProgressHeat.vue";
import RecentRuns from "./components/RecentRuns.vue";
import TrendChart from "./components/TrendChart.vue";
import UgcFunnel from "./components/UgcFunnel.vue";
import UgcScatter from "./components/UgcScatter.vue";
import UgcTable from "./components/UgcTable.vue";
import { fetchDashboard } from "./api/dashboard";
import { compact, duration, number, obstacleLabel, percent, platform } from "./utils/format";

const days = ref(7);
const data = ref(null);
const loading = ref(true);
const error = ref("");
const lastUpdated = ref("");
const animationKey = ref(0);
let controller = null;
let refreshTimer = null;

const kpis = computed(() => data.value?.kpis || {});
const deltas = computed(() => data.value?.deltas || {});
const trend = computed(() => data.value?.trend || []);
const platforms = computed(() => data.value?.platforms || []);
const mainLevels = computed(() => data.value?.main_levels || []);
const ugc = computed(() => data.value?.ugc || { funnel: {}, levels: [] });
const progressBins = computed(() => data.value?.collisions?.progress_bins || []);
const collisionTypes = computed(() => (data.value?.collisions?.by_type || []).slice(0, 5));
const chokeLevels = computed(() => data.value?.choke_levels || []);
const recentRuns = computed(() => data.value?.recent_runs || []);
const hasData = computed(() => Number(kpis.value.total_events || 0) > 0);
const isEmpty = computed(() => data.value && !hasData.value);
const topUgc = computed(() => ugc.value.levels?.[0] || null);
const lowestMain = computed(() => {
  const rows = [...mainLevels.value].filter((item) => item.runs >= 3);
  return rows.sort((a, b) => a.completion_rate - b.completion_rate)[0] || null;
});
const activePlatform = computed(() => {
  const found = [...platforms.value].sort((a, b) => b.runs - a.runs)[0];
  return found ? platform(found.id).label : "三端";
});
const platformTicker = computed(() =>
  platforms.value.map((item) => `${platform(item.id).short} ${percent(item.share, 0)}`).join("  ·  "),
);
const avgCompletion = computed(() => Number(kpis.value.completion_rate || 0));
const spark = (key) => trend.value.map((item) => Number(item[key]) || 0);
const kpiFormatter = (value) => number(value);
const percentFormatter = (value) => `${Number(value).toFixed(1)}%`;
const durationFormatter = (value) => duration(value);

function formatWindow(daysValue) {
  return daysValue === 1 ? "今日" : `近 ${daysValue} 天`;
}

async function load({ silent = false } = {}) {
  controller?.abort();
  controller = new AbortController();
  if (!silent) {
    loading.value = true;
  }
  error.value = "";
  try {
    const result = await fetchDashboard(days.value, controller.signal);
    data.value = result;
    animationKey.value += 1;
    lastUpdated.value = result.generated_at || new Date().toISOString();
  } catch (reason) {
    if (reason?.name === "CanceledError" || reason?.code === "ERR_CANCELED") return;
    error.value = reason?.response?.data?.error || reason?.message || "无法连接看板接口";
  } finally {
    loading.value = false;
  }
}

watch(days, () => load());

onMounted(() => {
  load();
  refreshTimer = window.setInterval(() => {
    if (!document.hidden) load({ silent: true });
  }, 60_000);
});

onBeforeUnmount(() => {
  controller?.abort();
  window.clearInterval(refreshTimer);
});
</script>

<template>
  <div class="app-shell">
    <div class="sky-decor" aria-hidden="true">
      <span class="sun-disc"></span>
      <svg class="cloud cloud-a" viewBox="0 0 220 76"><path d="M20 58c-12 0-20-8-20-18s8-18 20-18c3-13 14-22 28-22 13 0 24 8 28 20 4-2 9-3 14-3 14 0 25 10 25 23 0 10-8 18-19 18H20Z" fill="currentColor"/></svg>
      <svg class="cloud cloud-b" viewBox="0 0 220 76"><path d="M20 58c-12 0-20-8-20-18s8-18 20-18c3-13 14-22 28-22 13 0 24 8 28 20 4-2 9-3 14-3 14 0 25 10 25 23 0 10-8 18-19 18H20Z" fill="currentColor"/></svg>
      <svg class="cloud cloud-c" viewBox="0 0 220 76"><path d="M20 58c-12 0-20-8-20-18s8-18 20-18c3-13 14-22 28-22 13 0 24 8 28 20 4-2 9-3 14-3 14 0 25 10 25 23 0 10-8 18-19 18H20Z" fill="currentColor"/></svg>
      <svg class="hills" viewBox="0 0 1440 320" preserveAspectRatio="none">
        <path d="M0 250C150 180 280 210 410 250c150 46 250-90 410-80 150 9 240 95 350 100 110 5 190-55 270-75v125H0Z" fill="#b6f0c8" opacity=".62"/>
        <path d="M0 285c170-45 300 18 455 10 165-8 240-75 405-45 150 28 250 82 370 70 80-8 140-40 210-55v55H0Z" fill="#78dfa8" opacity=".62"/>
      </svg>
      <span class="hill-dot dot-a"></span>
      <span class="hill-dot dot-b"></span>
    </div>

    <div class="frame">
      <AppHeader
        :days="days"
        :loading="loading"
        :updated-at="lastUpdated"
        :live="!error"
        @update:days="days = $event"
        @refresh="load()"
      />

      <div v-if="error" class="error-bar" role="alert">
        <span class="error-mark">!</span>
        <div>
          <strong>数据接口没有回应</strong>
          <p>{{ error }} · 请确认后端已运行：<code>cd server &amp;&amp; npm start</code></p>
        </div>
        <button type="button" @click="load()">重新连接</button>
      </div>

      <section class="hero">
        <div class="hero-copy">
          <p class="hero-eyebrow"><span></span> PLAYGROUND PULSE / {{ formatWindow(days) }}</p>
          <h2>今天的乐园，<br /><em>正在发光。</em></h2>
          <p class="hero-sub">
            {{ activePlatform }} 是当前最热闹的站台。用卡点分布找“劝退路段”，用 UGC 热度决定下一张推荐图。
          </p>
          <div class="hero-ticker">
            <span class="ticker-dot"></span>
            <span>{{ platformTicker || "等待三端数据汇入" }}</span>
          </div>
          <div class="hero-stamp">☀️ 快乐运营中</div>
        </div>
        <div class="hero-score">
          <div class="score-ring" :style="{ '--score': `${avgCompletion * 3.6}deg` }">
            <div class="score-inner">
              <strong>{{ avgCompletion.toFixed(0) }}<small>%</small></strong>
              <span>全局通关率</span>
            </div>
          </div>
          <div class="hero-facts">
            <div><span>活跃关卡</span><strong>{{ number(kpis.active_levels) }}</strong></div>
            <div><span>事件样本</span><strong>{{ compact(kpis.total_events) }}</strong></div>
            <div><span>独立玩家</span><strong>{{ number(kpis.unique_players) }}</strong></div>
            <div><span>救下乘客</span><strong>{{ compact(kpis.saved_passengers) }}</strong></div>
          </div>
        </div>
      </section>

      <div v-if="isEmpty" class="empty-banner">
        <span class="empty-banner-icon">🎈</span>
        <p><strong>看板已就绪，轨道还没有留下数据。</strong> 进入一局主线或 UGC 关卡，结算后第一条记录就会出现在这里。</p>
      </div>

      <section v-if="loading && !data" class="skeleton-grid" aria-label="加载中">
        <div v-for="index in 6" :key="index" class="skeleton-card"></div>
        <div class="skeleton-wide"></div>
      </section>

      <template v-else>
        <section :key="`kpi-${animationKey}`" class="kpi-grid" aria-label="全局概览">
          <KpiCard
            label="总游玩次数"
            :value="kpis.runs"
            :formatter="kpiFormatter"
            :delta="deltas.runs"
            hint="主线 + UGC 的结算"
            icon="🚡"
            accent="#06d6a0"
            soft="#d9fff5"
            :spark="spark('runs')"
          />
          <KpiCard
            label="独立玩家"
            :value="kpis.unique_players"
            :formatter="kpiFormatter"
            :delta="deltas.unique_players"
            hint="按 player_id 去重"
            icon="🧑"
            accent="#63b3ed"
            soft="#e2f3ff"
            :spark="spark('players')"
          />
          <KpiCard
            label="全局通关率"
            :value="kpis.completion_rate"
            :formatter="percentFormatter"
            :delta="deltas.completion_rate"
            hint="通关 / 全部结算"
            icon="⭐"
            accent="#ffd166"
            soft="#fff2c7"
            :spark="spark('completion_rate')"
          />
          <KpiCard
            label="平均通关时长"
            :value="kpis.avg_time"
            :formatter="durationFormatter"
            :delta="deltas.avg_time"
            inverse-delta
            hint="仅统计通关局"
            icon="⏱"
            accent="#ff6b6b"
            soft="#ffe1df"
          />
          <KpiCard
            label="碰撞事件"
            :value="kpis.collisions"
            :formatter="kpiFormatter"
            :delta="deltas.collisions"
            inverse-delta
            :hint="`每局 ${Number(kpis.collisions_per_run || 0).toFixed(2)} 次`"
            icon="💥"
            accent="#ff6b6b"
            soft="#ffe1df"
            :spark="spark('collisions')"
          />
          <KpiCard
            label="UGC 进入次数"
            :value="ugc.funnel?.enters"
            :formatter="kpiFormatter"
            hint="进入 → 劝退 → 热度"
            icon="🗺"
            accent="#ffd166"
            soft="#fff2c7"
            :spark="trend.map((item) => item.runs)"
          />
        </section>

        <section :key="`grid-${animationKey}`" class="dashboard-grid">
          <ChartCard
            class="span-8"
            title="游玩趋势"
            eyebrow="PLAYBACK RHYTHM"
            hint="每日结算、通关、碰撞与通关率。碰撞柱越低，关卡手感越干净。"
            accent="#06d6a0"
            :empty="!hasData"
          >
            <TrendChart :trend="trend" />
            <template #footer>
              <div class="mini-legend">
                <span><i style="background:#06d6a0"></i>游玩</span>
                <span><i style="background:#ffd166"></i>通关</span>
                <span><i style="background:#ff6b6b"></i>碰撞</span>
                <span><i class="dash"></i>通关率</span>
                <em>{{ formatWindow(days) }} · 按 UTC 日期归档</em>
              </div>
            </template>
          </ChartCard>

          <ChartCard
            class="span-4"
            title="三端用户游玩情况"
            eyebrow="PLATFORM SPLIT"
            hint="Windows / Android / 微信小游戏。"
            accent="#63b3ed"
            :empty="platforms.length === 0"
          >
            <PlatformPanel :platforms="platforms" />
          </ChartCard>

          <ChartCard
            class="span-8"
            title="玩家卡点分布"
            eyebrow="CHOKE POINT HEAT"
            hint="把失败进度和碰撞进度叠在同一根时间轴，快速定位劝退路段。"
            accent="#ff6b6b"
            :empty="progressBins.every((item) => !item.collisions && !item.failures)"
          >
            <ProgressHeat :bins="progressBins" />
            <template #footer>
              <div class="mix-row">
                <span class="mix-label">碰撞构成</span>
                <span v-for="item in collisionTypes" :key="item.id" class="mix-chip">
                  {{ obstacleLabel(item.id) }} <b>{{ number(item.count) }}</b>
                </span>
                <em v-if="collisionTypes.length === 0">暂无碰撞样本</em>
              </div>
            </template>
          </ChartCard>

          <ChartCard
            class="span-4"
            title="卡点关卡排行"
            eyebrow="WHERE TO FIX"
            hint="失败次数 × 2 + 碰撞次数，综合排序。"
            accent="#ffd166"
            :empty="chokeLevels.length === 0"
          >
            <ChokeList :levels="chokeLevels" />
          </ChartCard>

          <ChartCard
            class="span-7"
            title="主线关卡通关率"
            eyebrow="MAINLINE CLEAR RATE"
            hint="按游玩量排序；颜色从珊瑚过渡到薄荷。"
            accent="#06d6a0"
            :empty="mainLevels.length === 0"
          >
            <MainLevelChart :levels="mainLevels" />
          </ChartCard>

          <ChartCard
            class="span-5"
            title="UGC 劝退率 × 热度"
            eyebrow="UGC SIGNAL"
            hint="右上角是高热度但劝退严重的关卡，优先调难度。"
            accent="#ff6b6b"
            :empty="ugc.levels.length === 0"
          >
            <UgcScatter :levels="ugc.levels" />
          </ChartCard>

          <ChartCard
            class="span-4"
            title="UGC 转化漏斗"
            eyebrow="COMMUNITY FUNNEL"
            hint="从进入、开始到完成，哪一层掉得最狠。"
            accent="#06d6a0"
            :empty="!ugc.funnel?.enters && !ugc.funnel?.runs"
          >
            <UgcFunnel :funnel="ugc.funnel || {}" />
            <template #footer>
              <div class="ugc-insight">
                <span class="insight-mark">💡</span>
                <p v-if="topUgc">
                  最热 UGC 是 <b>{{ topUgc.name }}</b>，劝退率
                  <em>{{ Number(topUgc.churn_rate).toFixed(0) }}%</em>；优先检查出生点与中段障碍密度。
                </p>
                <p v-else-if="lowestMain">
                  主线最低通关率：<b>{{ lowestMain.name }}</b>
                  <em>{{ Number(lowestMain.completion_rate).toFixed(0) }}%</em>，建议下调该段障碍速度。
                </p>
                <p v-else>等待更多 UGC 数据后，这里会自动给出运营提示。</p>
              </div>
            </template>
          </ChartCard>

          <ChartCard
            class="span-4"
            title="UGC 热度榜"
            eyebrow="COMMUNITY TOP"
            hint="热度 = 游玩、进入、点赞、收藏的对数加权。"
            accent="#ffd166"
            :empty="ugc.levels.length === 0"
          >
            <UgcTable :levels="ugc.levels" :limit="6" />
          </ChartCard>

          <ChartCard
            class="span-4"
            title="实时结算流"
            eyebrow="LIVE FEED"
            hint="最近 12 条结算，进入后一分钟自动刷新。"
            accent="#63b3ed"
            :empty="recentRuns.length === 0"
          >
            <RecentRuns :runs="recentRuns" :limit="8" />
          </ChartCard>
        </section>

        <footer class="dash-footer">
          <span>🚡 缆车大冒险 · CABLE CAR ADVENTURE</span>
          <span class="footer-track"><i></i></span>
          <span>数据源 /api/telemetry · 只展示聚合结果</span>
        </footer>
      </template>
    </div>
  </div>
</template>

<style scoped>
.app-shell {
  position: relative;
  min-height: 100vh;
  overflow: hidden;
  padding: 28px clamp(16px, 3vw, 46px) 34px;
}
.frame { position: relative; z-index: 2; max-width: 1580px; margin: 0 auto; }

.sky-decor {
  position: fixed;
  inset: 0;
  z-index: 0;
  overflow: hidden;
  pointer-events: none;
}
.sun-disc {
  position: absolute;
  right: 8%;
  top: 6%;
  width: 132px;
  height: 132px;
  border: 3px solid rgba(29, 53, 87, 0.09);
  border-radius: 50%;
  background: radial-gradient(circle at 35% 30%, #fff7c7, #ffd166 70%);
  box-shadow: 0 0 0 18px rgba(255, 209, 102, 0.13), 0 0 0 38px rgba(255, 209, 102, 0.07);
  animation: sun-pulse 5s ease-in-out infinite;
}
.cloud {
  position: absolute;
  width: 220px;
  color: rgba(255, 255, 255, 0.72);
  filter: drop-shadow(0 8px 0 rgba(255, 255, 255, 0.18));
  animation: cloud-drift 22s ease-in-out infinite alternate;
}
.cloud-a { top: 11%; left: -40px; transform: scale(0.9); }
.cloud-b { top: 22%; right: 4%; width: 170px; animation-duration: 28s; animation-delay: -6s; }
.cloud-c { top: 62%; left: 3%; width: 140px; opacity: 0.65; animation-duration: 34s; animation-delay: -12s; }
.hills {
  position: absolute;
  left: 0;
  right: 0;
  bottom: -2px;
  width: 100%;
  height: 34vh;
  min-height: 240px;
}
.hill-dot {
  position: absolute;
  border: 2px solid rgba(29, 53, 87, 0.12);
  border-radius: 50%;
  background: var(--yellow);
  opacity: 0.55;
}
.dot-a { left: 12%; bottom: 16%; width: 12px; height: 12px; }
.dot-b { right: 18%; bottom: 9%; width: 18px; height: 18px; background: var(--coral); opacity: 0.35; }

.hero {
  position: relative;
  display: flex;
  justify-content: space-between;
  gap: 30px;
  align-items: center;
  margin-bottom: 16px;
  padding: 25px 28px;
  border: var(--border);
  border-radius: 26px;
  background:
    radial-gradient(circle at 8% 15%, rgba(255, 255, 255, 0.72), transparent 28%),
    var(--cream);
  box-shadow: var(--shadow-card);
  overflow: hidden;
}
.hero::before {
  content: "";
  position: absolute;
  right: -50px;
  bottom: -90px;
  width: 270px;
  height: 190px;
  border-radius: 50%;
  background: var(--mint-soft);
  opacity: 0.8;
}
.hero::after {
  content: "";
  position: absolute;
  left: 22px;
  right: 22px;
  bottom: 9px;
  height: 2px;
  background: repeating-linear-gradient(90deg, rgba(29, 53, 87, 0.12) 0 6px, transparent 6px 12px);
}
.hero-copy { position: relative; z-index: 1; max-width: 660px; }
.hero-eyebrow {
  display: flex;
  align-items: center;
  gap: 8px;
  margin: 0 0 9px;
  color: var(--navy-soft);
  font-family: var(--font-mono);
  font-size: 8px;
  font-weight: 700;
  letter-spacing: 0.16em;
}
.hero-eyebrow span { width: 20px; height: 3px; border-radius: 3px; background: var(--coral); }
.hero h2 {
  margin: 0;
  color: var(--navy);
  font-family: var(--font-display);
  font-size: clamp(30px, 3.4vw, 48px);
  line-height: 1.05;
  letter-spacing: -0.02em;
  font-weight: 900;
}
.hero h2 em { color: var(--coral); font-style: normal; }
.hero-sub {
  max-width: 520px;
  margin: 11px 0 0;
  color: var(--muted);
  font-size: 11px;
  line-height: 1.7;
}
.hero-ticker {
  display: inline-flex;
  align-items: center;
  gap: 7px;
  margin-top: 13px;
  padding: 5px 9px;
  border: 1.5px solid var(--navy);
  border-radius: 999px;
  background: var(--paper);
  color: var(--navy-soft);
  font-family: var(--font-mono);
  font-size: 8px;
  box-shadow: 0 2px 0 var(--navy);
}
.ticker-dot { width: 5px; height: 5px; border-radius: 50%; background: var(--coral); }
.hero-stamp {
  position: absolute;
  right: 0;
  bottom: 25px;
  padding: 5px 10px;
  border: 2px solid var(--navy);
  border-radius: 8px;
  color: var(--navy);
  background: var(--yellow);
  font-size: 9px;
  font-weight: 700;
  transform: rotate(-4deg);
  box-shadow: 0 2px 0 var(--navy);
}
.hero-score { position: relative; z-index: 1; display: flex; align-items: center; gap: 24px; flex: 0 0 auto; }
.score-ring {
  width: 150px;
  height: 150px;
  border: var(--border);
  border-radius: 50%;
  display: grid;
  place-items: center;
  background:
    radial-gradient(circle at 50% 50%, var(--cream) 58%, transparent 59%),
    conic-gradient(var(--coral) 0deg, var(--yellow) var(--score), var(--mint) var(--score) 360deg);
  box-shadow: 0 6px 0 var(--navy), inset 0 0 0 5px rgba(255, 255, 255, 0.3);
  animation: ring-pop 0.9s cubic-bezier(0.34, 1.56, 0.64, 1) both;
}
.score-inner { display: flex; flex-direction: column; align-items: center; }
.score-inner strong {
  color: var(--navy);
  font-family: var(--font-display);
  font-size: 40px;
  font-weight: 900;
  line-height: 1;
  letter-spacing: -0.04em;
}
.score-inner small { color: var(--coral); font-size: 14px; }
.score-inner span { margin-top: 4px; color: var(--muted); font-size: 9px; }
.hero-facts { display: flex; flex-direction: column; gap: 8px; }
.hero-facts div {
  display: flex;
  flex-direction: column;
  padding: 5px 9px;
  border: 1.5px solid var(--navy);
  border-radius: 9px;
  background: var(--paper);
  box-shadow: 0 2px 0 var(--navy);
  min-width: 100px;
}
.hero-facts span { color: var(--muted); font-size: 8px; }
.hero-facts strong { color: var(--navy); font-family: var(--font-display); font-size: 14px; font-weight: 900; }

.error-bar {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-bottom: 14px;
  padding: 12px 14px;
  border: var(--border);
  border-radius: 16px;
  background: var(--coral-soft);
  box-shadow: var(--shadow-soft);
  color: var(--navy);
}
.error-mark {
  display: grid;
  place-items: center;
  width: 28px;
  height: 28px;
  border: 2px solid var(--navy);
  border-radius: 9px;
  background: var(--coral);
  color: #fff;
  font-weight: 900;
}
.error-bar strong { font-size: 12px; }
.error-bar p { margin: 2px 0 0; color: var(--muted); font-size: 10px; }
.error-bar code { color: var(--navy); font-family: var(--font-mono); font-weight: 700; }
.error-bar button {
  margin-left: auto;
  border: 2px solid var(--navy);
  border-radius: 9px;
  background: var(--yellow);
  color: var(--navy);
  padding: 6px 12px;
  font-size: 10px;
  font-weight: 700;
  box-shadow: 0 3px 0 var(--navy);
  cursor: pointer;
}
.error-bar button:active { transform: translateY(2px); box-shadow: 0 1px 0 var(--navy); }
.empty-banner {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 14px;
  padding: 11px 14px;
  border: 2px dashed var(--navy);
  border-radius: 14px;
  background: rgba(255, 244, 210, 0.72);
  color: var(--muted);
  font-size: 11px;
}
.empty-banner-icon { font-size: 20px; }
.empty-banner p { margin: 0; }
.empty-banner strong { color: var(--navy); }

.kpi-grid { display: grid; grid-template-columns: repeat(6, minmax(0, 1fr)); gap: 12px; margin-bottom: 12px; }
.kpi-grid > * { animation: pop-in 0.62s cubic-bezier(0.34, 1.56, 0.64, 1) both; }
.kpi-grid > :nth-child(2) { animation-delay: 0.05s; }
.kpi-grid > :nth-child(3) { animation-delay: 0.1s; }
.kpi-grid > :nth-child(4) { animation-delay: 0.15s; }
.kpi-grid > :nth-child(5) { animation-delay: 0.2s; }
.kpi-grid > :nth-child(6) { animation-delay: 0.25s; }
.dashboard-grid { display: grid; grid-template-columns: repeat(12, minmax(0, 1fr)); gap: 12px; }
.dashboard-grid > * { animation-delay: calc(var(--i, 0) * 60ms); }
.dashboard-grid > :nth-child(1) { --i: 0; }
.dashboard-grid > :nth-child(2) { --i: 1; }
.dashboard-grid > :nth-child(3) { --i: 2; }
.dashboard-grid > :nth-child(4) { --i: 3; }
.dashboard-grid > :nth-child(5) { --i: 4; }
.dashboard-grid > :nth-child(6) { --i: 5; }
.dashboard-grid > :nth-child(7) { --i: 6; }
.dashboard-grid > :nth-child(8) { --i: 7; }
.dashboard-grid > :nth-child(9) { --i: 8; }
.span-4 { grid-column: span 4; }
.span-5 { grid-column: span 5; }
.span-7 { grid-column: span 7; }
.span-8 { grid-column: span 8; }

.mini-legend { display: flex; align-items: center; gap: 13px; color: var(--muted); font-size: 9px; }
.mini-legend span { display: inline-flex; align-items: center; gap: 5px; }
.mini-legend i { display: inline-block; width: 13px; height: 4px; border-radius: 2px; }
.mini-legend i.dash { height: 0; border-top: 2px dashed #63b3ed; }
.mini-legend em { margin-left: auto; color: var(--muted); font-style: normal; font-size: 8px; }
.mix-row { display: flex; align-items: center; flex-wrap: wrap; gap: 7px; }
.mix-label { color: var(--muted); font-size: 9px; margin-right: 2px; }
.mix-chip {
  padding: 3px 7px;
  border: 1.5px solid var(--navy);
  border-radius: 999px;
  color: var(--navy);
  background: var(--paper);
  font-size: 9px;
  font-weight: 700;
  box-shadow: 0 2px 0 var(--navy);
}
.mix-chip b { color: var(--coral); font-family: var(--font-mono); margin-left: 2px; }
.mix-row em { color: var(--muted); font-size: 9px; font-style: normal; }
.ugc-insight { display: flex; align-items: flex-start; gap: 8px; }
.insight-mark {
  display: grid;
  place-items: center;
  width: 23px;
  height: 23px;
  flex: 0 0 23px;
  border: 2px solid var(--navy);
  border-radius: 7px;
  background: var(--yellow-soft);
  box-shadow: 0 2px 0 var(--navy);
  font-size: 12px;
}
.ugc-insight p { margin: 1px 0 0; color: var(--muted); font-size: 9px; line-height: 1.6; }
.ugc-insight b { color: var(--navy); font-weight: 700; }
.ugc-insight em { color: var(--coral); font-style: normal; font-family: var(--font-mono); font-weight: 700; }

.skeleton-grid { display: grid; grid-template-columns: repeat(6, 1fr); gap: 12px; }
.skeleton-card,
.skeleton-wide {
  border: var(--border);
  border-radius: 20px;
  background: linear-gradient(100deg, var(--cream) 10%, #fff9e8 20%, var(--cream) 30%);
  background-size: 200% 100%;
  box-shadow: var(--shadow-card);
  animation: shimmer 1.4s linear infinite;
}
.skeleton-card { height: 126px; }
.skeleton-wide { grid-column: span 6; height: 340px; }

.dash-footer {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 27px 2px 4px;
  color: var(--navy-soft);
  font-family: var(--font-mono);
  font-size: 8px;
  font-weight: 700;
  letter-spacing: 0.06em;
}
.footer-track { flex: 1; height: 3px; border-radius: 3px; background: rgba(29, 53, 87, 0.14); position: relative; }
.footer-track i {
  position: absolute;
  left: 0;
  top: -3px;
  width: 9px;
  height: 9px;
  border: 1.5px solid var(--navy);
  border-radius: 50%;
  background: var(--coral);
}

@keyframes cloud-drift { to { transform: translate3d(34px, 10px, 0) scale(1.04); } }
@keyframes sun-pulse { 50% { transform: scale(1.04); } }
@keyframes ring-pop { from { transform: scale(0.72) rotate(-16deg); opacity: 0; } to { transform: none; opacity: 1; } }
@keyframes pop-in { from { opacity: 0; transform: translateY(24px) scale(0.94); } to { opacity: 1; transform: none; } }
@keyframes shimmer { to { background-position: -200% 0; } }

@media (max-width: 1320px) {
  .kpi-grid { grid-template-columns: repeat(3, 1fr); }
  .kpi-grid > * { min-width: 0; }
}
@media (max-width: 1100px) {
  .hero { align-items: flex-start; }
  .hero-score { gap: 14px; }
  .score-ring { width: 116px; height: 116px; }
  .score-inner strong { font-size: 31px; }
  .span-8, .span-7, .span-5, .span-4 { grid-column: span 12; }
}
@media (max-width: 720px) {
  .app-shell { padding: 18px 11px 24px; }
  .hero { flex-direction: column; padding: 20px; }
  .hero-score { width: 100%; justify-content: space-between; }
  .hero-stamp { display: none; }
  .kpi-grid { grid-template-columns: repeat(2, 1fr); }
  .kpi-grid > * { min-height: 118px; }
  .mini-legend em { display: none; }
  .skeleton-grid { grid-template-columns: repeat(2, 1fr); }
  .skeleton-wide { grid-column: span 2; }
  .cloud { opacity: 0.45; }
}
@media (max-width: 440px) {
  .kpi-grid { grid-template-columns: 1fr; }
  .hero-facts { display: none; }
}
</style>
