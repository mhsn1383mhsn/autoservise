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

// 4) Safe area: وب‌ویو را از زیر نوار وضعیت/ناوبری بیرون می‌آوریم (روی همهٔ نسخه‌های اندروید یکسان کار می‌کند)
(function patchMainActivity() {
  const base = path.join(root, 'android', 'app', 'src', 'main', 'java');
  const found = [];
  (function walk(d) {
    if (!fs.existsSync(d)) return;
    for (const n of fs.readdirSync(d)) {
      const p = path.join(d, n);
      if (fs.statSync(p).isDirectory()) walk(p);
      else if (n === 'MainActivity.java') found.push(p);
    }
  })(base);
  if (!found.length) throw new Error('MainActivity.java not found');
  for (const f of found) {
    const old = fs.readFileSync(f, 'utf8');
    const pkg = (old.match(/^\s*package\s+[^;]+;/m) || [''])[0];
    const code = `${pkg}

import android.graphics.Color;
import android.os.Bundle;
import android.view.View;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.core.view.WindowInsetsControllerCompat;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        WindowCompat.setDecorFitsSystemWindows(getWindow(), false);
        getWindow().setStatusBarColor(Color.TRANSPARENT);
        getWindow().setNavigationBarColor(Color.TRANSPARENT);
        final View content = findViewById(android.R.id.content);
        content.setBackgroundColor(Color.parseColor("#0B0B0D"));
        ViewCompat.setOnApplyWindowInsetsListener(content, (v, insets) -> {
            Insets bars = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() | WindowInsetsCompat.Type.displayCutout());
            Insets ime = insets.getInsets(WindowInsetsCompat.Type.ime());
            v.setPadding(bars.left, bars.top, bars.right, Math.max(bars.bottom, ime.bottom));
            return WindowInsetsCompat.CONSUMED;
        });
        WindowInsetsControllerCompat c =
            WindowCompat.getInsetsController(getWindow(), getWindow().getDecorView());
        c.setAppearanceLightStatusBars(false);
        c.setAppearanceLightNavigationBars(false);
    }
}
`;
    fs.writeFileSync(f, code);
    console.log('patch-android: MainActivity patched ->', f);
  }
})();
