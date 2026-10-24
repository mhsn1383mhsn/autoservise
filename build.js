// خروجی www/index.html را از src/index.html می‌سازد: اسکریپت مبهم‌سازی و HTML فشرده می‌شود.
const fs = require('fs');
const path = require('path');
const JavaScriptObfuscator = require('javascript-obfuscator');
const { minify } = require('html-minifier-terser');

(async () => {
  const src = fs.readFileSync(path.join(__dirname, 'src', 'index.html'), 'utf8');
  const re = /<script>([\s\S]*?)<\/script>/g;
  let best = null, m;
  while ((m = re.exec(src))) { if (!best || m[1].length > best[1].length) best = m; }
  if (!best) throw new Error('inline <script> not found');

  const obf = JavaScriptObfuscator.obfuscate(best[1], {
    compact: true,
    renameGlobals: false,              // توابع سراسری تغییر نام نمی‌دهند (امن برای handlerها)
    identifierNamesGenerator: 'hexadecimal',
    stringArray: true,
    stringArrayThreshold: 0.75,
    stringArrayEncoding: ['base64'],
    stringArrayWrappersCount: 2,
    splitStrings: true,
    splitStringsChunkLength: 8,
    controlFlowFlattening: false,      // برای سرعت روی گوشی خاموش است
    deadCodeInjection: false,
    selfDefending: false,
    debugProtection: false,
    unicodeEscapeSequence: false
  }).getObfuscatedCode();

  let html = src.replace(best[0], () => '<script>' + obf + '</script>');
  html = await minify(html, {
    collapseWhitespace: true,
    removeComments: true,
    minifyCSS: true,
    minifyJS: false
  });

  const out = path.join(__dirname, 'www');
  fs.mkdirSync(out, { recursive: true });
  fs.writeFileSync(path.join(out, 'index.html'), html);
  for (const size of [32, 144, 180, 192, 512]) fs.copyFileSync(path.join(__dirname, `icon-${size}.png`), path.join(out, `icon-${size}.png`));
  console.log('built www/index.html', (html.length / 1024).toFixed(0) + ' KB');
})().catch(e => { console.error(e); process.exit(1); });
