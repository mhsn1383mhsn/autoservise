// آیکون اختصاصی + Edge-to-Edge (نوار وضعیت/ناوبری شفاف)
const fs = require('fs'), path = require('path');
const root = path.join(__dirname, '..');
const brand = path.join(root, 'branding', 'android');
const res = path.join(root, 'android', 'app', 'src', 'main', 'res');
if (!fs.existsSync(brand)) throw new Error('branding/android not found');
if (!fs.existsSync(res)) throw new Error('android/app/src/main/res not found — run cap add android first');

const rm = p => { if (fs.existsSync(p)) fs.rmSync(p, { force: true, recursive: true }); };

// 1) حذف آیکون پیش‌فرض Capacitor
rm(path.join(res, 'drawable-v24', 'ic_launcher_foreground.xml'));
for (const d of fs.readdirSync(res)) {
  if (!d.startsWith('mipmap-')) continue;
  for (const f of fs.readdirSync(path.join(res, d))) {
    if (f.startsWith('ic_launcher')) rm(path.join(res, d, f));
  }
}

// 2) کپی آیکون اختصاصی
let n = 0;
for (const sub of fs.readdirSync(brand)) {
  const from = path.join(brand, sub), to = path.join(res, sub);
  if (!fs.statSync(from).isDirectory()) continue;
  fs.mkdirSync(to, { recursive: true });
  for (const f of fs.readdirSync(from)) {
    fs.copyFileSync(path.join(from, f), path.join(to, f));
    n++;
  }
}
console.log('patch-android: copied', n, 'icon files');

// 3) Manifest
const mp = path.join(root, 'android', 'app', 'src', 'main', 'AndroidManifest.xml');
let m = fs.readFileSync(mp, 'utf8');
m = m.replace(/android:icon="[^"]*"/, 'android:icon="@mipmap/ic_launcher"')
     .replace(/android:roundIcon="[^"]*"/, 'android:roundIcon="@mipmap/ic_launcher_round"');
fs.writeFileSync(mp, m);
console.log('patch-android: manifest icons OK');

// 4) themes — نوار شفاف + cutout
(function patchThemes() {
  const valuesDirs = fs.readdirSync(res).filter(d => d.startsWith('values'));
  for (const vd of valuesDirs) {
    for (const name of ['styles.xml', 'themes.xml']) {
      const fp = path.join(res, vd, name);
      if (!fs.existsSync(fp)) continue;
      let t = fs.readFileSync(fp, 'utf8');
      t = t.replace(/<item name="android:statusBarColor">[^<]*<\/item>/g,
        '<item name="android:statusBarColor">@android:color/transparent</item>');
      t = t.replace(/<item name="android:navigationBarColor">[^<]*<\/item>/g,
        '<item name="android:navigationBarColor">@android:color/transparent</item>');
      if (!t.includes('windowLayoutInDisplayCutoutMode')) {
        t = t.replace(/(<\/style>)/,
          '    <item name="android:statusBarColor">@android:color/transparent</item>\n' +
          '    <item name="android:navigationBarColor">@android:color/transparent</item>\n' +
          '    <item name="android:windowLayoutInDisplayCutoutMode">shortEdges</item>\n' +
          '    <item name="android:windowDrawsSystemBarBackgrounds">true</item>\n$1');
      }
      fs.writeFileSync(fp, t);
      console.log('patch-android: themes ->', fp);
    }
  }
  const v27 = path.join(res, 'values-v27');
  fs.mkdirSync(v27, { recursive: true });
  fs.writeFileSync(path.join(v27, 'styles.xml'), `<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="AppTheme" parent="Theme.AppCompat.NoActionBar">
        <item name="android:statusBarColor">@android:color/transparent</item>
        <item name="android:navigationBarColor">@android:color/transparent</item>
        <item name="android:windowLayoutInDisplayCutoutMode">shortEdges</item>
        <item name="android:windowDrawsSystemBarBackgrounds">true</item>
        <item name="android:enforceStatusBarContrast">false</item>
        <item name="android:enforceNavigationBarContrast">false</item>
        <item name="android:windowBackground">#0B0B0D</item>
    </style>
</resources>
`);
  console.log('patch-android: values-v27 OK');
})();

// 5) MainActivity Edge-to-Edge
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
    const pkg = (old.match(/^\s*package\s+[^;]+;/m) || ['package com.autoservice.app;'])[0];
    const code = `${pkg}

import android.graphics.Color;
import android.os.Bundle;
import android.view.View;
import android.webkit.JavascriptInterface;
import android.webkit.WebView;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.core.view.WindowInsetsControllerCompat;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    private volatile int insTop = 0, insRight = 0, insBottom = 0, insLeft = 0;

    public class InsetsBridge {
        @JavascriptInterface public int top() { return insTop; }
        @JavascriptInterface public int right() { return insRight; }
        @JavascriptInterface public int bottom() { return insBottom; }
        @JavascriptInterface public int left() { return insLeft; }
        @JavascriptInterface public void setLightBars(final boolean light) {
            runOnUiThread(new Runnable() {
                @Override public void run() {
                    WindowInsetsControllerCompat c =
                        WindowCompat.getInsetsController(getWindow(), getWindow().getDecorView());
                    c.setAppearanceLightStatusBars(light);
                    c.setAppearanceLightNavigationBars(light);
                }
            });
        }
    }

    @Override
    public void onCreate(Bundle savedInstanceState) {
        // قبل از super فقط رنگ‌ها؛ دست زدن به DecorView قبل از super باعث نوار عنوان می‌شود
        getWindow().setStatusBarColor(Color.TRANSPARENT);
        getWindow().setNavigationBarColor(Color.TRANSPARENT);
        if (android.os.Build.VERSION.SDK_INT >= 28) {
            getWindow().setNavigationBarDividerColor(Color.TRANSPARENT);
        }

        super.onCreate(savedInstanceState);
        // بعد از super — تمام‌صفحه و رنگ پس‌زمینه
        WindowCompat.setDecorFitsSystemWindows(getWindow(), false);
        getWindow().getDecorView().setBackgroundColor(Color.parseColor("#0B0B0D"));
        // کیبورد: تغییر اندازه محتوا
        getWindow().setSoftInputMode(android.view.WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);

        WindowInsetsControllerCompat bars =
            WindowCompat.getInsetsController(getWindow(), getWindow().getDecorView());
        bars.setAppearanceLightStatusBars(false);
        bars.setAppearanceLightNavigationBars(false);

        final float density = getResources().getDisplayMetrics().density;

        getBridge().getWebView().post(new Runnable() {
            @Override public void run() {
                if (getBridge() != null && getBridge().getWebView() != null) {
                    getBridge().getWebView().addJavascriptInterface(new InsetsBridge(), "AndroidInsets");
                }
            }
        });

        final View content = findViewById(android.R.id.content);
        ViewCompat.setOnApplyWindowInsetsListener(content, (v, insets) -> {
            Insets sys = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() | WindowInsetsCompat.Type.displayCutout());
            Insets ime = insets.getInsets(WindowInsetsCompat.Type.ime());
            boolean imeShown = insets.isVisible(WindowInsetsCompat.Type.ime());
            v.setPadding(0, 0, 0, imeShown ? ime.bottom : 0);

            insTop = Math.round(sys.top / density);
            insRight = Math.round(sys.right / density);
            insLeft = Math.round(sys.left / density);
            insBottom = imeShown ? 0 : Math.round(sys.bottom / density);

            if (getBridge() != null && getBridge().getWebView() != null) {
                final WebView wv = getBridge().getWebView();
                final String js = "window.__setInsets&&window.__setInsets("
                    + insTop + "," + insRight + "," + insBottom + "," + insLeft + ")";
                wv.post(new Runnable() {
                    @Override public void run() { wv.evaluateJavascript(js, null); }
                });
            }
            return WindowInsetsCompat.CONSUMED;
        });
        ViewCompat.requestApplyInsets(content);
    }
}
`;
    fs.writeFileSync(f, code);
    console.log('patch-android: MainActivity edge-to-edge ->', f);
  }
})();

// 6) خنثی‌کردن splash: تصویر splash حذف و با رنگ ساده تیره جایگزین می‌شود
(function neutralizeSplash() {
  let removed = 0;
  (function walk(d) {
    for (const n of fs.readdirSync(d)) {
      const p = path.join(d, n);
      if (fs.statSync(p).isDirectory()) { if (n.startsWith('drawable')) walk(p); }
      else if (/^splash(_dark)?\.(png|jpg|webp|xml)$/.test(n) && path.basename(d).startsWith('drawable')) { fs.rmSync(p, { force: true }); removed++; }
    }
  })(res);
  const dd = path.join(res, 'drawable');
  fs.mkdirSync(dd, { recursive: true });
  fs.writeFileSync(path.join(dd, 'splash.xml'),
    '<?xml version="1.0" encoding="utf-8"?>\n<shape xmlns:android="http://schemas.android.com/apk/res/android">\n    <solid android:color="#0B0B0D"/>\n</shape>\n');
  console.log('patch-android: splash neutralized, removed', removed, 'files');
})();

console.log('patch-android: done');
