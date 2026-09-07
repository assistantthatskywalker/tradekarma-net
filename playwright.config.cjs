const { defineConfig } = require('@playwright/test');
module.exports = defineConfig({
  testDir: './test/web', timeout: 30000, use: { baseURL: 'http://127.0.0.1:18546',
    launchOptions: process.env.CHROME_EXECUTABLE ? { executablePath: process.env.CHROME_EXECUTABLE } : {},
  }, webServer: { command: 'node scripts/serve-site.cjs', url: 'http://127.0.0.1:18546', reuseExistingServer: false },
  projects: [{ name: 'desktop', use: { viewport: { width: 1440, height: 1000 } } }, { name: 'mobile', use: { viewport: { width: 390, height: 844 } } }],
});
