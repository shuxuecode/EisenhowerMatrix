// Service Worker — 离线缓存 PWA 资源
const CACHE_NAME = 'eisenhower-matrix-v1';
const ASSETS_TO_CACHE = [
  './',
  './index.html',
  './css/style.css',
  './js/app.js',
  './image/favicon.png',
  './image/icon-192.png',
  './image/icon-512.png',
  './manifest.json'
];

// 安装：预缓存核心资源
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => cache.addAll(ASSETS_TO_CACHE))
      .then(() => self.skipWaiting())
  );
});

// 激活：清理旧缓存
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(
        keys.filter((key) => key !== CACHE_NAME)
          .map((key) => caches.delete(key))
      ))
      .then(() => self.clients.claim())
  );
});

// 请求拦截：缓存优先，失败再网络（适合静态资源）
self.addEventListener('fetch', (event) => {
  // GitHub API 请求不走缓存（动态数据）
  if (event.request.url.includes('api.github.com')) {
    event.respondWith(
      fetch(event.request)
        .catch(() => new Response(JSON.stringify({ error: '网络不可用' }), {
          status: 503,
          headers: { 'Content-Type': 'application/json' }
        }))
    );
    return;
  }

  event.respondWith(
    caches.match(event.request)
      .then((cached) => {
        if (cached) return cached;
        return fetch(event.request)
          .then((response) => {
            // 只缓存成功的 GET 请求
            if (response.ok && event.request.method === 'GET') {
              const clone = response.clone();
              caches.open(CACHE_NAME)
                .then((cache) => cache.put(event.request, clone));
            }
            return response;
          })
          .catch(() => {
            // 网络失败且无缓存时，返回离线页面（仅对导航请求）
            if (event.request.mode === 'navigate') {
              return caches.match('./index.html');
            }
            return new Response('离线不可用', { status: 503 });
          });
      })
  );
});