const { chromium } = require('playwright');

async function run() {
    console.log("Launching headless browser...");
    const browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();
    
    // Listen for all network requests
    page.on('request', request => {
        const url = request.url();
        if (url.includes('wingsdatabase.com')) {
            console.log(`\n[Request to wingsdatabase]:`);
            console.log(`URL: ${url}`);
            console.log(`Method: ${request.method()}`);
            console.log(`Headers:`, JSON.stringify(request.headers(), null, 2));
        }
    });

    // Listen for all network responses to capture data
    page.on('response', async response => {
        const url = response.url();
        if (url.includes('wingsdatabase.com')) {
            console.log(`[Response from wingsdatabase]:`);
            console.log(`Status: ${response.status()}`);
            try {
                const text = await response.text();
                console.log(`Body (truncated): ${text.substring(0, 1000)}`);
            } catch (e) {
                console.log("Could not read body:", e.message);
            }
        }
    });

    try {
        console.log("Navigating to cineby.at/movie/862...");
        await page.goto('https://www.cineby.at/movie/862', { waitUntil: 'networkidle', timeout: 30000 });
        
        console.log("Waiting for player to load...");
        await page.waitForTimeout(5000);
        
        console.log("Attempting to click play button if present...");
        // Click play button or trigger play
        const playBtn = await page.$('button:has-text("Play"), .play-btn, svg path[d*="M8"]');
        if (playBtn) {
            await playBtn.click();
            console.log("Clicked play button!");
        } else {
            // Click center of screen
            await page.mouse.click(600, 400);
            console.log("Clicked screen center!");
        }
        
        console.log("Monitoring traffic for 15 seconds...");
        await page.waitForTimeout(15000);
    } catch (e) {
        console.error("Error during browser run:", e);
    } finally {
        await browser.close();
        console.log("Browser closed.");
    }
}

run();
