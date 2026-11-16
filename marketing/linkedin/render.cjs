// Renders launch.html to launch.png at 2x (2160 x 2700) with headless Chromium-based Brave.
// Usage: node marketing/linkedin/render.cjs  (needs marketing/screenshots' node_modules installed)
const path = require('node:path');
const { chromium } = require(path.join(__dirname, '../screenshots/node_modules/playwright'));

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.BROWSER_PATH ?? '/Applications/Brave Browser.app/Contents/MacOS/Brave Browser',
    headless: true,
  });
  const page = await browser.newPage({ viewport: { width: 1080, height: 1350 }, deviceScaleFactor: 2 });
  await page.goto('file://' + path.join(__dirname, 'launch.html'), { waitUntil: 'networkidle' });
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({ path: path.join(__dirname, 'launch.png') });
  await browser.close();
  console.log('saved', path.join(__dirname, 'launch.png'));
})().catch((e) => {
  console.error('failed:', e.message);
  process.exit(1);
});
