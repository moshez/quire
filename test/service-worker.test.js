/**
 * Service worker tests
 *
 * Validates:
 * - Cache name and shell asset list
 * - Install event caches all shell assets
 * - Fetch event returns cached responses (cache-first)
 * - Fetch event falls back to network on cache miss
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { readFileSync } from 'fs';
import { resolve } from 'path';

// Parse service-worker.js to extract constants
const swSource = readFileSync(resolve(__dirname, '../service-worker.js'), 'utf8');

describe('Service Worker Source', () => {
  it('should define cache name quire-v1', () => {
    expect(swSource).toContain("const CACHE = 'quire-v1'");
  });

  it('should define SHELL with all app shell assets', () => {
    expect(swSource).toContain("'/'");
    expect(swSource).toContain("'/bridge.js'");
    expect(swSource).toContain("'/quire.wasm'");
    expect(swSource).toContain("'/reader.css'");
    expect(swSource).toContain("'/manifest.json'");
  });

  it('should register install event listener', () => {
    expect(swSource).toContain("self.addEventListener('install'");
  });

  it('should register fetch event listener', () => {
    expect(swSource).toContain("self.addEventListener('fetch'");
  });

  it('should use caches.open with CACHE name in install', () => {
    expect(swSource).toContain('caches.open(CACHE)');
  });

  it('should use caches.match in fetch handler', () => {
    expect(swSource).toContain('caches.match(e.request)');
  });

  it('should fall back to fetch on cache miss', () => {
    expect(swSource).toContain('fetch(e.request)');
  });
});

describe('Service Worker Behavior', () => {
  let listeners;
  let mockCache;
  let mockCaches;

  beforeEach(() => {
    listeners = {};
    mockCache = {
      addAll: vi.fn(() => Promise.resolve()),
      match: vi.fn(() => Promise.resolve(undefined)),
      put: vi.fn(() => Promise.resolve()),
    };
    mockCaches = {
      open: vi.fn(() => Promise.resolve(mockCache)),
      match: vi.fn(() => Promise.resolve(undefined)),
    };

    // Create a minimal service worker environment
    const self = {
      addEventListener: (event, handler) => {
        listeners[event] = handler;
      },
    };

    // Execute the service worker in a simulated scope
    const fn = new Function('self', 'caches', 'fetch', swSource);
    fn(self, mockCaches, vi.fn());
  });

  it('should register install and fetch listeners', () => {
    expect(typeof listeners.install).toBe('function');
    expect(typeof listeners.fetch).toBe('function');
  });

  it('should cache all shell assets on install', async () => {
    const waitUntilPromise = { current: null };
    const event = {
      waitUntil: (p) => { waitUntilPromise.current = p; },
    };

    listeners.install(event);
    await waitUntilPromise.current;

    expect(mockCaches.open).toHaveBeenCalledWith('quire-v1');
    expect(mockCache.addAll).toHaveBeenCalledWith([
      '/', '/bridge.js', '/quire.wasm', '/reader.css', '/manifest.json'
    ]);
  });

  it('should respond with cached content when available (cache-first)', async () => {
    const cachedResponse = new Response('cached');
    mockCaches.match.mockResolvedValue(cachedResponse);

    let respondedWith = null;
    const event = {
      request: new Request('http://localhost/bridge.js'),
      respondWith: (p) => { respondedWith = p; },
    };

    listeners.fetch(event);
    const response = await respondedWith;

    expect(response).toBe(cachedResponse);
  });

  it('should fall back to network on cache miss', async () => {
    mockCaches.match.mockResolvedValue(undefined);
    const networkResponse = new Response('from network');
    const mockFetch = vi.fn(() => Promise.resolve(networkResponse));

    // Re-create with custom fetch
    const listeners2 = {};
    const self2 = {
      addEventListener: (event, handler) => {
        listeners2[event] = handler;
      },
    };
    const fn = new Function('self', 'caches', 'fetch', swSource);
    fn(self2, mockCaches, mockFetch);

    let respondedWith = null;
    const event = {
      request: new Request('http://localhost/unknown.js'),
      respondWith: (p) => { respondedWith = p; },
    };

    listeners2.fetch(event);
    const response = await respondedWith;

    expect(response).toBe(networkResponse);
  });
});

describe('PWA Assets', () => {
  it('should have manifest.json', () => {
    const manifest = JSON.parse(
      readFileSync(resolve(__dirname, '../manifest.json'), 'utf8')
    );
    expect(manifest.name).toBe('Quire');
    expect(manifest.display).toBe('standalone');
    expect(manifest.icons).toHaveLength(2);
    expect(manifest.icons[0].sizes).toBe('192x192');
    expect(manifest.icons[1].sizes).toBe('512x512');
  });

  it('should have icon-192.png', () => {
    const icon = readFileSync(resolve(__dirname, '../icon-192.png'));
    // PNG magic bytes
    expect(icon[0]).toBe(0x89);
    expect(icon[1]).toBe(0x50); // P
    expect(icon[2]).toBe(0x4E); // N
    expect(icon[3]).toBe(0x47); // G
  });

  it('should have icon-512.png', () => {
    const icon = readFileSync(resolve(__dirname, '../icon-512.png'));
    // PNG magic bytes
    expect(icon[0]).toBe(0x89);
    expect(icon[1]).toBe(0x50);
    expect(icon[2]).toBe(0x4E);
    expect(icon[3]).toBe(0x47);
  });

  it('should have reader.css with loading screen styles', () => {
    const css = readFileSync(resolve(__dirname, '../reader.css'), 'utf8');
    expect(css).toContain('.quire-loading');
    expect(css).toContain('quire-spin');
    expect(css).toContain('@keyframes');
  });

  it('should have service worker registration in index.html', () => {
    const html = readFileSync(resolve(__dirname, '../index.html'), 'utf8');
    expect(html).toContain("navigator.serviceWorker.register");
    expect(html).toContain('service-worker.js');
    expect(html).toContain('theme-color');
    expect(html).toContain('manifest.json');
  });
});
