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
        Object.defineProperty(navigator, 'plugins', { get: () => [1, 2, 3] });
        Object.defineProperty(navigator, 'languages', { get: () => ['en-US', 'en'] });
    });
    
    // We do NOT listen to console to prevent triggering the RegToString Checker!
    
    // Listen for requests to capture wingsdatabase traffic
    page.on('request', request => {
        const url = request.url();
        if (url.includes('wingsdatabase.com')) {
            console.log(`\n[Request to wingsdatabase]:`);
            console.log(`URL: ${url}`);
            console.log(`Method: ${request.method()}`);
            console.log(`Headers:`, JSON.stringify(request.headers(), null, 2));
        }
    });

    page.on('response', async response => {
        const url = response.url();
        if (url.includes('wingsdatabase.com')) {
            console.log(`[Response from wingsdatabase]:`);
            console.log(`Status: ${response.status()}`);
            try {
                const text = await response.text();
                console.log(`Body (truncated): ${text.substring(0, 500)}`);
            } catch (e) {
                console.log("Could not read body:", e.message);
            }
        }
    });

    try {
        console.log("Navigating to https://www.cineby.at/movie/862...");
        await page.goto('https://www.cineby.at/movie/862', { waitUntil: 'networkidle', timeout: 30000 });
        
        console.log("Waiting for player to load and fetch streams...");
        await page.waitForTimeout(10000);
        
        // Let's click play or interaction to be safe
        await page.mouse.click(600, 400);
        console.log("Clicked page center.");
        
        await page.waitForTimeout(10000);
        
        console.log("Taking screenshot to verify page loaded...");
        await page.screenshot({ path: 'cineby_loaded.png' });
        console.log("Screenshot saved.");
    } catch (e) {
        console.error("Navigation error:", e);
    } finally {
        await browser.close();
        console.log("Browser closed.");
    }
}

run();
