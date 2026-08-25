import { cpus, freemem, loadavg, totalmem } from "node:os";

export const HOST_PRESSURE_EFFECTS = Object.freeze(["host.cpu-count", "host.load-average-1m", "host.memory"]);

export function readHostPressureEvidence() {
  const total = totalmem();
  if (!Number.isFinite(total) || total <= 0) throw new Error("host total memory is unavailable");
  return Object.freeze({
    ok: true,
    availableMemoryPercent: (freemem() / total) * 100,
    loadAverage1m: loadavg()[0],
    cpuCount: cpus().length,
  });
}

