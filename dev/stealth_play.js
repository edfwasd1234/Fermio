const { chromium } = require('playwright');

async function run() {
    console.log("Launching browser with stealth and play trigger...");
    const browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();
    
    // Stealth init script
    await page.addInitScript(() => {
        const noop = () => {};
        window.console = {
            log: noop,
            warn: noop,
            error: noop,
            info: noop,
            clear: noop,
            debug: noop,
            trace: noop
        };
        Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
        Object.defineProperty(navigator, 'plugins', { get: () => [1, 2, 3] });
        Object.defineProperty(navigator, 'languages', { get: () => ['en-US', 'en'] });
    });
    
    // Intercept requests
    page.on('request', request => {
        const url = request.url();
        if (url.includes('wingsdatabase.com')) {
            console.log(`\n[Request]: ${url}`);
            console.log(`Headers:`, JSON.stringify(request.headers(), null, 2));
        }
    });

    page.on('response', async response => {
        const url = response.url();
        if (url.includes('wingsdatabase.com')) {
            console.log(`[Response status]: ${response.status()}`);
            try {
                const text = await response.text();
                console.log(`Body (truncated): ${text.substring(0, 500)}`);
            } catch (e) {
                console.log("Body not readable:", e.message);
            }
        }
    });

    try {
        console.log("Navigating...");
        await page.goto('https://www.cineby.at/movie/862', { waitUntil: 'networkidle', timeout: 30000 });
        await page.waitForTimeout(3000);
        
        console.log("Clicking the Play button...");
        // Look for the play button
        const playBtn = await page.$('button:has-text("Play")');
        if (playBtn) {
            await playBtn.click();
            console.log("Play button clicked!");
        } else {
            console.log("Play button not found! Clicking screen center...");
            await page.mouse.click(600, 400);
        }
        
        console.log("Waiting 15 seconds to capture player load traffic...");
        await page.waitForTimeout(15000);
        
        await page.screenshot({ path: 'cineby_playing.png' });
        console.log("Saved cineby_playing.png");
    } catch (e) {
        console.error(e);
    } finally {
        await browser.close();
    }
}

run();
