const fs = require("fs");
const path = require("path");
const http = require("http");
let chromium;
try {
  ({ chromium } = require("playwright"));
} catch {
  ({ chromium } = require("/Users/hs/.npm/_npx/9833c18b2d85bc59/node_modules/playwright"));
}

const CHROME_PATH = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const FILM_DIR = __dirname;

function startServer(rootDir) {
  return new Promise((resolve) => {
    const srv = http.createServer((req, res) => {
      const u = new URL(req.url, "http://127.0.0.1");
      if (u.pathname === "/favicon.ico") {
        res.writeHead(204);
        res.end();
        return;
      }
      let p = path.join(rootDir, decodeURIComponent(u.pathname === "/" ? "/film.html" : u.pathname));
      if (!p.startsWith(rootDir) || !fs.existsSync(p)) {
        res.writeHead(404);
        res.end("Not found");
        return;
      }
      const ext = path.extname(p).toLowerCase();
      const mime = ext === ".html" ? "text/html; charset=utf-8" : "application/octet-stream";
      res.writeHead(200, { "Content-Type": mime, "Cache-Control": "no-store" });
      res.end(fs.readFileSync(p));
    });
    srv.listen(0, "127.0.0.1", () => {
      resolve({ srv, port: srv.address().port });
    });
  });
}

async function run() {
  const args = process.argv.slice(2);
  const mode = args[0] || "--stills"; // --stills | --frames
  const ar = args[1] || "16x9"; // 16x9 | 9x16
  const outDir = args[2] || path.join(FILM_DIR, `${mode === "--stills" ? "stills" : "frames"}_${ar}`);
  const fps = Number(args[3] || 30);
  const workers = Number(args[4] || 4);

  const width = ar === "9x16" ? 1080 : 1920;
  const height = ar === "9x16" ? 1920 : 1080;

  fs.mkdirSync(outDir, { recursive: true });
  for (const f of fs.readdirSync(outDir)) {
    if (f.endsWith(".jpg") || f.endsWith(".png")) fs.unlinkSync(path.join(outDir, f));
  }

  const { srv, port } = await startServer(FILM_DIR);
  const brandParam = process.env.BRAND ? `&brand=${encodeURIComponent(process.env.BRAND)}` : "";
  const url = `http://127.0.0.1:${port}/film.html?ar=${ar}${brandParam}`;
  const errors = [];

  const browser = await chromium.launch({
    executablePath: CHROME_PATH,
    headless: true,
    args: ["--disable-gpu-vsync", "--font-render-hinting=none", "--hide-scrollbars"]
  });

  const tStart = Date.now();

  if (mode === "--stills") {
    const context = await browser.newContext({ viewport: { width, height }, deviceScaleFactor: 1 });
    const page = await context.newPage();
    page.on("pageerror", (e) => errors.push(`pageerror: ${e.message}`));
    page.on("console", (m) => { if (m.type() === "error") errors.push(`console.error: ${m.text()}`); });

    await page.goto(url, { waitUntil: "load" });
    await page.waitForFunction(() => window.__ready === true, null, { timeout: 10000 });

    const stamps = [0.95, 2.36, 4.10, 5.35, 7.65, 8.95, 10.30, 12.40, 14.20, 16.40, 19.40, 22.85, 25.15, 27.45, 28.80, 30.60, 33.80, 37.60];
    for (const ts of stamps) {
      await page.evaluate((x) => {
        window.__renderAt(x);
        void document.getElementById("stage").offsetHeight;
      }, ts);
      const fname = `t_${ts.toFixed(2).padStart(5, "0")}.jpg`;
      await page.screenshot({ path: path.join(outDir, fname), type: "jpeg", quality: 92 });
    }
    await context.close();
    console.log(`[stills ${ar}] ${stamps.length} stills saved to ${outDir} in ${((Date.now() - tStart) / 1000).toFixed(1)}s, errors=${errors.length}`);
  } else {
    // Contiguous sequential chunks per worker (zero round-robin cross-tab interleaving!)
    const context = await browser.newContext({ viewport: { width, height }, deviceScaleFactor: 1 });
    const pages = await Promise.all(Array.from({ length: workers }, async () => {
      const p = await context.newPage();
      p.on("pageerror", (e) => errors.push(`pageerror: ${e.message}`));
      p.on("console", (m) => { if (m.type() === "error") errors.push(`console.error: ${m.text()}`); });
      await p.goto(url, { waitUntil: "load" });
      await p.waitForFunction(() => window.__ready === true, null, { timeout: 10000 });
      return p;
    }));

    const dur = await pages[0].evaluate(() => window.__DUR);
    const totalFrames = Math.round(dur * fps);
    const chunkSize = Math.ceil(totalFrames / workers);
    console.log(`[frames ${ar}] rendering ${totalFrames} frames (${dur}s @ ${fps}fps) across ${workers} contiguous worker chunks (chunk=${chunkSize})...`);

    let doneCount = 0;
    await Promise.all(pages.map(async (p, wIdx) => {
      const startIdx = wIdx * chunkSize;
      const endIdx = Math.min(totalFrames, startIdx + chunkSize);
      for (let idx = startIdx; idx < endIdx; idx++) {
        const t = idx / fps;
        await p.evaluate((ts) => {
          window.__renderAt(ts);
          void document.getElementById("stage").offsetHeight;
        }, t);
        const fname = `frame_${String(idx).padStart(5, "0")}.jpg`;
        await p.screenshot({ path: path.join(outDir, fname), type: "jpeg", quality: 95 });
        doneCount++;
        if (doneCount % 300 === 0 || doneCount === totalFrames) {
          console.log(`  progress: ${doneCount}/${totalFrames} (${((Date.now() - tStart) / 1000).toFixed(1)}s)`);
        }
      }
    }));

    await context.close();
    console.log(`[frames ${ar}] DONE ${totalFrames} frames in ${((Date.now() - tStart) / 1000).toFixed(1)}s, errors=${errors.length}`);
  }

  await browser.close();
  srv.close();
  if (errors.length > 0) {
    console.error("ERRORS:", errors);
    process.exit(1);
  }
}

run().catch((err) => {
  console.error(err);
  process.exit(1);
});
