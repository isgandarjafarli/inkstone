// Makes the App Store iPhone screenshots (6.9-inch, 1320 x 2868) from the raw simulator
// screenshots that the cloud build saves on the ci-results branch.
// Usage: node appstore/tools/render.js <folder with raw screenshots> <output folder>
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const slides = [
  ['01-lock-screen', 'light-widgets-lock.png', 'Chinese on your<br><em>lock screen</em>', 'A new HSK word every time you check the time.'],
  ['02-sentences', 'light-word.png', 'Every word in<br><em>real sentences</em>', 'Pinyin over every character. Tap any word to look it up.'],
  ['03-tones', 'light-word-long.png', 'See the<br><em>tones</em>', 'Each tone has its own colour, on pinyin and on characters.'],
  ['04-writing', 'light-char.png', 'Write every<br><em>character</em>', 'Watch the strokes, trace them, then write from memory.'],
  ['05-today', 'light-today.png', 'A few words<br><em>a day</em>', 'Reviews come back just before you would forget.'],
  ['06-widgets', 'light-widgets-home.png', 'Widgets<br>that <em>teach</em>', 'Mark a word known or skip to the next, right on your home screen.'],
];

(async () => {
  const [src, out] = process.argv.slice(2);
  if (!src || !out) { console.error('usage: node render.js <raw screenshots> <output>'); process.exit(1); }
  fs.mkdirSync(out, { recursive: true });
  const template = fs.readFileSync(path.join(__dirname, 'slide.html'), 'utf8');
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1320, height: 2868 }, deviceScaleFactor: 1 });
  for (const [name, shot, h1, p] of slides) {
    const img = 'file://' + path.resolve(src, shot);
    const html = template.replace('__H1__', h1).replace('__P__', p).replace('__IMG__', img).replace('__TOP__', '760');
    const tmp = path.join(out, '.tmp.html');
    fs.writeFileSync(tmp, html);
    await page.goto('file://' + path.resolve(tmp));
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(200);
    await page.screenshot({ path: path.join(out, name + '.jpg'), type: 'jpeg', quality: 92 });
    fs.unlinkSync(tmp);
    console.log('wrote', name);
  }
  await browser.close();
})();
