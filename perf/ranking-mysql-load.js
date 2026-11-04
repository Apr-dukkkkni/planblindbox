import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter } from 'k6/metrics';

const vus = Number(__ENV.VUS || '50');
const stage = __ENV.STAGE_SECONDS || '20s';
const pause = Number(__ENV.SLEEP_SECONDS || '0.2');
const url = __ENV.TARGET_URL || 'http://host.docker.internal:8092/api/v1/mods/ranking?limit=10';

// These counters are written to k6-summary.json automatically.
const failedTotal = new Counter('ranking_failed_total');
const failedHttp4xx = new Counter('ranking_failed_http_4xx');
const failedHttp429 = new Counter('ranking_failed_http_429');
const failedHttp5xx = new Counter('ranking_failed_http_5xx');
const failedHttpOther = new Counter('ranking_failed_http_other');
const failedNetwork = new Counter('ranking_failed_network');

export const options = {
  stages: [
    { duration: stage, target: Math.max(1, Math.round(vus * 0.2)) },
    { duration: stage, target: Math.max(1, Math.round(vus * 0.6)) },
    { duration: stage, target: vus },
    { duration: stage, target: 0 },
  ],
  thresholds: {
    http_req_failed: ['rate<0.01'],
    checks: ['rate>0.99'],
  },
};

export default function () {
  const res = http.get(url, { timeout: '10s' });
  const ok = res.status === 200;
  check(res, { 'HTTP 200': () => ok });
  if (!ok) {
    failedTotal.add(1);
    if (res.status === 0) {
      failedNetwork.add(1);
    } else if (res.status === 429) {
      failedHttp429.add(1);
      failedHttp4xx.add(1);
    } else if (res.status >= 400 && res.status < 500) {
      failedHttp4xx.add(1);
    } else if (res.status >= 500 && res.status < 600) {
      failedHttp5xx.add(1);
    } else {
      failedHttpOther.add(1);
    }
    // Error codes matter for status=0. Only failures are logged.
    console.error(`ranking_failure status=${res.status} error_code=${res.error_code || 0} error=${res.error || 'none'} url=${url}`);
  }
  sleep(pause);
}
