# اتو سرویس — ساخت APK با گیتهاب

## ۱. ساخت مخزن
1. در GitHub یک مخزن جدید بسازید و حتماً **Private** انتخاب کنید.
2. همهٔ فایل‌های این پوشه (از جمله پوشهٔ `.github`) را در آن آپلود کنید.
   فایل `src/index.html` سورس خوانای برنامه است و فقط داخل مخزن خصوصی می‌ماند.

## ۲. گرفتن APK
1. در مخزن به تب **Actions** بروید و workflow به نام **Build Android APK** را انتخاب کنید.
2. دکمهٔ **Run workflow** را بزنید و چند دقیقه صبر کنید.
3. بعد از اتمام، داخل صفحهٔ اجرا در بخش **Artifacts** فایل `auto-service-apk` را دانلود کنید.
   (اگر Secrets تنظیم نکرده باشید، APK از نوع Debug ساخته می‌شود؛ روی گوشی نصب می‌شود ولی برای انتشار در مارکت مناسب نیست.)

## ۳. APK امضاشده (Release) — اختیاری
۱. روی کامپیوتری که Java دارد یک keystore بسازید (فقط یک‌بار و آن را مطمئن نگه دارید):

    keytool -genkey -v -keystore release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias autoservice

۲. آن را به Base64 تبدیل کنید:
   - لینوکس/مک: `base64 -w0 release.jks`
   - ویندوز (PowerShell): `[Convert]::ToBase64String([IO.File]::ReadAllBytes("release.jks"))`

۳. در مخزن: Settings → Secrets and variables → Actions → New repository secret. این چهار Secret را بسازید:
   - `KEYSTORE_BASE64` (خروجی مرحلهٔ قبل)
   - `KEYSTORE_PASSWORD`
   - `KEY_ALIAS` (مثلاً `autoservice`)
   - `KEY_PASSWORD`

فایل `release.jks` را هرگز داخل مخزن نگذارید و یک نسخهٔ پشتیبان امن از آن نگه دارید؛ بدون آن نمی‌توانید آپدیت بدهید.

## نکات
- هر تغییری در `src/index.html` بدهید و commit کنید، بیلد جدید خودکار اجرا می‌شود.
- آدرس Supabase و کلید `anon` داخل برنامه عمومی‌اند؛ کلید خصوصی لایسنس فقط در Supabase است.


## آیکون برنامه
آیکون قرمز/مشکی در `assets/` قرار دارد. هنگام ساخت APK، دستور `npx capacitor-assets generate --android` منابع لانچر اندروید را تولید می‌کند؛ سپس `npx cap sync android` آن‌ها را همگام می‌کند. برای دیدن آیکون جدید، APK جدید را بسازید و نصب کنید. اگر نسخه قبلی نصب است و آیکون کش شده، حذف و نصب مجدد را امتحان کنید.
