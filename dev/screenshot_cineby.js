const { chromium } = require('playwright');

async function run() {
    console.log("Launching browser...");
    const browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();
    try {
        console.log("Navigating to https://www.cineby.at/movie/862...");
        const response = await page.goto('https://www.cineby.at/movie/862', { timeout: 30000 });
        console.log("Response Status:", response.status());
        const html = await page.content();
        console.log("HTML Start:", html.substring(0, 1000));
    } catch (e) {
        console.error(e);
    } finally {
        await browser.close();
    }
}

run();
