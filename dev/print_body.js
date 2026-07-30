const { chromium } = require('playwright');

async function run() {
    console.log("Launching browser with console blocker...");
    const browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();
    
    // Add init script to remove webdriver and block console formatting
    await page.addInitScript(() => {
        // Redefine console methods to be completely empty
        const noop = () => {};
        window.console = {
            log: noop,
            warn: noop,
            error: noop,
            info: noop,
            clear: noop,
            debug: noop,
            trace: noop,
            dir: noop,
            group: noop,
            groupEnd: noop,
            time: noop,
            timeEnd: noop
        };
        
        Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
        Object.defineProperty(navigator, 'plugins', { get: () => [1, 2, 3] });
        Object.defineProperty(navigator, 'languages', { get: () => ['en-US', 'en'] });
    });
    
    try {
        console.log("Navigating...");
        await page.goto('https://www.cineby.at/movie/862', { waitUntil: 'networkidle', timeout: 30000 });
        await page.waitForTimeout(5000);
        
        const bodyHTML = await page.evaluate(() => document.body.innerHTML);
        console.log("Body length:", bodyHTML.length);
        console.log("Body content snippet (first 1000 chars):");
        console.log(bodyHTML.substring(0, 1000));
        
        await page.screenshot({ path: 'cineby_loaded.png' });
        console.log("Screenshot saved.");
    } catch (e) {
        console.error(e);
    } finally {
        await browser.close();
    }
}

run();
