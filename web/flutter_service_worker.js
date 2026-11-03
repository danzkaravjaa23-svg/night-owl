'use strict';

// Retire older Flutter offline workers without navigating open tabs. Existing
// drafts keep running; index.html handles a bounded refresh only during startup.
self.addEventListener('install', function (event) {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', function (event) {
  event.waitUntil(self.registration.unregister().catch(function () {}));
});
