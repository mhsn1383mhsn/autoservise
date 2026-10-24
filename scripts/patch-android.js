// آیکون اختصاصی را روی پروژهٔ اندروید می‌نشاند و آیکون پیش‌فرض Capacitor (X آبی) را کنار می‌گذارد.
const fs = require('fs'), path = require('path');
const root = path.join(__dirname, '..');
const brand = path.join(root, 'branding', 'android');
const res = path.join(root, 'android', 'app', 'src', 'main', 'res');
if (!fs.existsSync(brand)) throw new Error('branding/android not found');
if (!fs.existsSync(res)) throw new Error('android/app/src/main/res not found');

// 1) فایل‌های پیش‌فرض قدیمی حذف شوند
const rm = p => { if (fs.existsSync(p)) fs.rmSync(p, { force: true }); };
rm(path.join(res, 'drawable-v24', 'ic_launcher_foreground.xml'));
for (const d of fs.readdirSync(res)) {
  if (!d.startsWith('mipmap-')) continue;
  for (const f of fs.readdirSync(path.join(res, d))) {
    if (f.startsWith('ic_launcher')) rm(path.join(res, d, f));
  }
}

// 2) آیکون‌های اختصاصی کپی شوند
let n = 0;
for (const sub of fs.readdirSync(brand)) {
  const from = path.join(brand, sub), to = path.join(res, sub);
  if (!fs.statSync(from).isDirectory()) continue;
  fs.mkdirSync(to, { recursive: true });
  for (const f of fs.readdirSync(from)) { fs.copyFileSync(path.join(from, f), path.join(to, f)); n++; }
}
console.log('patch-android: copied', n, 'icon files');

// 3) مطمئن شویم Manifest به همین آیکون‌ها اشاره می‌کند
const mp = path.join(root, 'android', 'app', 'src', 'main', 'AndroidManifest.xml');
let m = fs.readFileSync(mp, 'utf8');
m = m.replace(/android:icon="[^"]*"/, 'android:icon="@mipmap/ic_launcher"')
     .replace(/android:roundIcon="[^"]*"/, 'android:roundIcon="@mipmap/ic_launcher_round"');
fs.writeFileSync(mp, m);
console.log('patch-android: manifest icon ->', (m.match(/android:icon="[^"]*"/) || [])[0]);
