const { chromium } = require('playwright');

async function run() {
    const browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();
    try {
        await page.goto('https://www.cineby.at/movie/862', { waitUntil: 'networkidle' });
        await page.waitForTimeout(3000);
        
        // Print page title
        const title = await page.title();
        console.log("Title:", title);
        
        // Print all buttons
        const buttons = await page.evaluate(() => {
            return Array.from(document.querySelectorAll('button, a, div')).map(el => {
                const text = el.innerText || '';
                const className = el.className || '';
                const id = el.id || '';
                if (text.includes("Play") || className.includes("play") || id.includes("play")) {
                    return { tag: el.tagName, text: text.substring(0, 100).trim(), class: className, id: id };
                }
                return null;
            }).filter(Boolean);
        });
        console.log("Found interactive elements relating to play:", JSON.stringify(buttons, null, 2));
    } catch (e) {
        console.error(e);
    } finally {
        await browser.close();
    }
}

run();
