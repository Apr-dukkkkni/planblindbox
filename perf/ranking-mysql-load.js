import http from 'k6/http';
import { check, sleep } from 'k6';
const vus = Number(__ENV.VUS || '50');
const stage = __ENV.STAGE_SECONDS || '20s';
const pause = Number(__ENV.SLEEP_SECONDS || '0.2');
const url = __ENV.TARGET_URL || 'http://host.docker.internal:8092/api/v1/mods/ranking?limit=10';
export const options = {
  stages: [
    { duration: stage, target: Math.max(1, Math.round(vus * 0.2)) },
    { duration: stage, target: Math.max(1, Math.round(vus * 0.6)) },
    { duration: stage, target: vus },
    { duration: stage, target: 0 },
  ],
  thresholds: { http_req_failed: ['rate<0.01'], checks: ['rate>0.99'] },
};
export default function () {
  const res = http.get(url, { timeout: '10s' });
  check(res, { 'HTTP 200': r => r.status === 200 });
  sleep(pause);
}
