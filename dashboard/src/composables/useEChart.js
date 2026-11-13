import { onBeforeUnmount, onMounted, shallowRef, watch } from "vue";
import * as echarts from "echarts/core";
import { BarChart, FunnelChart, LineChart, PieChart, ScatterChart } from "echarts/charts";
import {
  DataZoomComponent,
  GraphicComponent,
  GridComponent,
  LegendComponent,
  MarkLineComponent,
  TooltipComponent,
} from "echarts/components";
import { CanvasRenderer } from "echarts/renderers";

echarts.use([
  BarChart,
  FunnelChart,
  LineChart,
  PieChart,
  ScatterChart,
  DataZoomComponent,
  GraphicComponent,
  GridComponent,
  LegendComponent,
  MarkLineComponent,
  TooltipComponent,
  CanvasRenderer,
]);

export function useEChart(containerRef, optionRef, { onInit } = {}) {
  const chart = shallowRef(null);
  let observer = null;

  function render() {
    if (!chart.value) return;
    const option = optionRef.value;
    if (option) {
      chart.value.setOption(option, { notMerge: true, lazyUpdate: true });
    }
  }

  onMounted(() => {
    if (!containerRef.value) return;
    chart.value = echarts.init(containerRef.value, null, { renderer: "canvas" });
    onInit?.(chart.value);
    render();
    observer = new ResizeObserver(() => chart.value?.resize());
    observer.observe(containerRef.value);
  });

  watch(optionRef, render, { deep: false });

  onBeforeUnmount(() => {
    observer?.disconnect();
    chart.value?.dispose();
    chart.value = null;
  });

  return chart;
}

export { echarts };
