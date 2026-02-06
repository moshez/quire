import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './e2e',
  timeout: 60000,
  expect: { timeout: 15000 },
  use: {
    baseURL: 'http://localhost:3737',
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
    viewport: { width: 1024, height: 768 },
    headless: true,
  },
  webServer: {
    command: 'npx serve . -l 3737 --no-clipboard',
    port: 3737,
    reuseExistingServer: !process.env.CI,
  },
  projects: [
    {
      name: 'chromium',
      use: {
        browserName: 'chromium',
        launchOptions: {
          args: [
            '--no-sandbox',
            '--disable-setuid-sandbox',
            '--disable-gpu',
            '--disable-dev-shm-usage',
            '--disable-software-rasterizer',
          ],
        },
      },
    },
  ],
});
