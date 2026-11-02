import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 10 },
    { duration: '30s', target: 30 },
    { duration: '30s', target: 50 },
    { duration: '30s', target: 0 },
  ],
};

export default function () {
  const res = http.get(
    'http://host.docker.internal:8091/api/v1/mods/ranking?limit=10'
  );

  check(res, {
    '排行榜返回200': (r) => r.status === 200,
  });

  sleep(1);
}
