(function bootstrapApi() {
  const localHosts = new Set(["localhost", "127.0.0.1"]);
  const defaultBaseUrl = localHosts.has(window.location.hostname)
    ? "http://localhost:8080/api/v1"
    : "/api/v1";
  const baseUrl = (window.LIGHTBITE_API_BASE_URL || defaultBaseUrl).replace(/\/$/, "");

  async function request(path, options = {}) {
    const response = await fetch(`${baseUrl}${path}`, {
      ...options,
      headers: {
        Accept: "application/json",
        ...(options.body ? { "Content-Type": "application/json" } : {}),
        ...options.headers,
      },
      credentials: "include",
    });

    const payload = response.status === 204 ? null : await response.json().catch(() => null);
    if (!response.ok) {
      const error = new Error(payload?.message || "请求失败，请稍后重试");
      error.status = response.status;
      error.code = payload?.code || "REQUEST_FAILED";
      error.details = payload;
      throw error;
    }
    return payload;
  }

  async function ping() {
    return request("/system/ping");
  }

  window.LightBiteApi = Object.freeze({ baseUrl, request, ping });

  const statusElement = document.querySelector("[data-api-status]");
  if (!statusElement) return;

  const controller = new AbortController();
  const timeoutId = window.setTimeout(() => controller.abort(), 2500);
  request("/system/ping", { signal: controller.signal })
    .then(() => {
      statusElement.textContent = "服务已连接";
      statusElement.dataset.state = "online";
    })
    .catch(() => {
      statusElement.textContent = "本地体验模式";
      statusElement.dataset.state = "offline";
    })
    .finally(() => window.clearTimeout(timeoutId));
})();
