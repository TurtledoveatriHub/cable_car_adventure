import axios from "axios";

const api = axios.create({
  // 开发环境走 Vite 代理；生产可在 .env 设置 VITE_API_BASE=https://域名/api
  baseURL: import.meta.env.VITE_API_BASE || "/api",
  timeout: 20000,
  headers: { Accept: "application/json" },
});

export async function fetchDashboard(days = 7, signal) {
  const response = await api.get("/telemetry/dashboard", {
    params: { days },
    signal,
  });
  if (!response.data?.ok) {
    throw new Error(response.data?.error || "看板接口返回异常");
  }
  return response.data;
}

export default api;
