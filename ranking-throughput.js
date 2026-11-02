import http from 'k6/http';
import { check } from 'k6';

export const options = {
    stages: [
        { duration: '20s', target: 10 },
        { duration: '20s', target: 30 },
        { duration: '20s', target: 50 },
        { duration: '20s', target: 100 },
        { duration: '20s', target: 0 },
    ],
    thresholds: {
        http_req_failed: ['rate<0.01'],
        http_req_duration: ['p(95)<500'],
    },
};

export default function () {
    const res = http.get(
        'http://host.docker.internal:8091/api/v1/mods/ranking?limit=10'
    );

    check(res, {
        '排行榜返回200': (r) => r.status === 200,
    });
}