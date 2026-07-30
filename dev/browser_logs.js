const { chromium } = require('playwright');

async function run() {
    console.log("Launching headless browser with stealth...");
    const browser = await chromium.launch({ headless: true });
    const context = await browser.newContext({
        userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        viewport: { width: 1280, height: 800 }
    });
    
    const page = await context.newPage();
    
    // Add init script to remove webdriver property
    await page.addInitScript(() => {
        Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
        // Also mock standard plugins/languages to look more human
        Object.defineProperty(navigator, 'plugins', { get: () => [1, 2, 3] });
        Object.defineProperty(navigator, 'languages', { get: () => ['en-US', 'en'] });
    });
    
    page.on('console', msg => console.log('PAGE LOG:', msg.text()));
    page.on('pageerror', err => console.log('PAGE ERROR:', err.message));
    
    try {
        console.log("Navigating to https://www.cineby.at/movie/862...");
        await page.goto('https://www.cineby.at/movie/862', { waitUntil: 'networkidle', timeout: 30000 });
        await page.waitForTimeout(5000);
        
        console.log("Taking screenshot...");
        await page.screenshot({ path: 'cineby_loaded.png' });
        console.log("Screenshot saved.");
    } catch (e) {
        console.error("Navigation error:", e);
    } finally {
        await browser.close();
    }
}

run();
