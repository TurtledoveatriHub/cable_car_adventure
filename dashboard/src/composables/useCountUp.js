import { onBeforeUnmount, onMounted, ref, watch } from "vue";

/**
 * 数字从 0 滚动到目标值。初次挂载也会完整播放，刷新后重新挂载即可再次触发。
 */
export function useCountUp(source, { duration = 950 } = {}) {
  const display = ref(0);
  let frame = 0;
  let startedAt = 0;
  let from = 0;
  let to = Number(source.value) || 0;

  function prefersReduced() {
    return window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches === true;
  }

  function tick(now) {
    if (prefersReduced()) {
      display.value = to;
      return;
    }
    const progress = Math.min(1, (now - startedAt) / duration);
    const eased = 1 - Math.pow(1 - progress, 4);
    display.value = from + (to - from) * eased;
    if (progress < 1) {
      frame = requestAnimationFrame(tick);
    } else {
      display.value = to;
    }
  }

  function start(fromValue = 0) {
    cancelAnimationFrame(frame);
    from = fromValue;
    to = Number(source.value) || 0;
    startedAt = performance.now();
    frame = requestAnimationFrame(tick);
  }

  onMounted(() => {
    if (prefersReduced()) {
      display.value = to;
      return;
    }
    start(0);
  });

  watch(source, () => start(display.value));

  onBeforeUnmount(() => cancelAnimationFrame(frame));

  return { display };
}
