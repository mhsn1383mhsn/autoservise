__PACKAGE__

import android.Manifest;
import android.app.Activity;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.telephony.SmsManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebView;

import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import org.json.JSONObject;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * پل ارسال پیامک. در JS با نام «AndroidSms» ثبت می‌شود
 * (تا اینترفیس قدیمی «Android» که کپی/واتساپ/تماس/چاپ دارد بازنویسی نشود).
 */
public class SmsBridge {

    private static final int DELAY_NORMAL_MS = 800;
    private static final int DELAY_LARGE_MS = 1500;   // بیش از ۵۰ پیامک
    private static final long REPORT_TIMEOUT_MS = 120_000;

    private final Activity activity;
    private final WebView webView;
    private final String actionSent;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final AtomicInteger seq = new AtomicInteger(1000);
    private final Map<String, Batch> batches = new ConcurrentHashMap<>();
    private volatile boolean bulkRunning = false;

    /** وضعیت یک ارسال (تکی یا گروهی) */
    private static class Batch {
        final String id;
        final boolean bulk;
        final int total;
        final String phone;               // فقط برای ارسال تکی
        int partsExpected = 0;
        int partsDone = 0;
        boolean dispatchDone = false;
        boolean reported = false;
        final Set<String> failed = new HashSet<>();

        Batch(String id, boolean bulk, int total, String phone) {
            this.id = id; this.bulk = bulk; this.total = total; this.phone = phone;
        }
    }

    private final BroadcastReceiver sentReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            Batch b = batches.get(intent.getStringExtra("batch"));
            if (b == null) return;
            String phone = intent.getStringExtra("phone");
            boolean ok = getResultCode() == Activity.RESULT_OK;
            synchronized (b) {
                b.partsDone++;
                if (!ok && phone != null) b.failed.add(phone);
            }
            maybeFinish(b);
        }
    };

    public SmsBridge(Activity activity, WebView webView) {
        this.activity = activity;
        this.webView = webView;
        this.actionSent = activity.getPackageName() + ".SMS_SENT";
        ContextCompat.registerReceiver(activity, sentReceiver,
                new IntentFilter(actionSent), ContextCompat.RECEIVER_NOT_EXPORTED);
    }

    /** از onDestroy فراخوانی شود */
    public void destroy() {
        try { activity.unregisterReceiver(sentReceiver); } catch (Exception ignored) {}
    }

    // ─── مجوز ───
    private boolean hasSmsPermission() {
        return ContextCompat.checkSelfPermission(activity, Manifest.permission.SEND_SMS)
                == PackageManager.PERMISSION_GRANTED;
    }

    @JavascriptInterface
    public boolean hasPermission() {
        return hasSmsPermission();
    }

    @JavascriptInterface
    public void requestSmsPermission() {
        activity.runOnUiThread(() -> {
            if (hasSmsPermission()) {
                jsCallback("onSmsPermission", "'granted'");
                return;
            }
            ActivityCompat.requestPermissions(activity,
                    new String[]{Manifest.permission.SEND_SMS}, 1001);
        });
    }

    // ─── ارسال تکی ───
    @JavascriptInterface
    public void sendSms(final String phone, final String message) {
        if (phone == null || phone.isEmpty() || message == null || message.isEmpty()) return;

        if (!hasSmsPermission()) {
            jsCallback("onSmsResult", "{\"ok\":false,\"error\":\"permission\"}");
            return;
        }

        String id = "single-" + seq.incrementAndGet();
        Batch b = new Batch(id, false, 1, phone);
        batches.put(id, b);
        try {
            dispatch(b, phone, message);
        } catch (Exception e) {
            batches.remove(id);
            jsCallback("onSmsResult", "{\"ok\":false,\"error\":" + q(e.getMessage()) + "}");
            return;
        }
        synchronized (b) { b.dispatchDone = true; }
        scheduleTimeout(b);
        maybeFinish(b);
    }

    // ─── ارسال گروهی ───
    @JavascriptInterface
    public void sendBulkSms(final String jsonPhones, final String message) {
        sendBulkSmsFast(jsonPhones, message);
    }

    @JavascriptInterface
    public void sendBulkSmsFast(final String jsonPhones, final String message) {
        if (!hasSmsPermission()) {
            jsCallback("onSmsBulkComplete",
                    "{\"ok\":false,\"error\":\"permission\",\"sent\":0,\"failed\":0}");
            return;
        }
        final ArrayList<String> phones = parsePhones(jsonPhones);
        if (phones.isEmpty() || message == null || message.isEmpty()) {
            jsCallback("onSmsBulkComplete",
                    "{\"ok\":false,\"error\":\"empty_list\",\"sent\":0,\"failed\":0}");
            return;
        }
        if (bulkRunning) {
            jsCallback("onSmsBulkComplete",
                    "{\"ok\":false,\"error\":\"busy\",\"sent\":0,\"failed\":0}");
            return;
        }
        bulkRunning = true;

        final String id = "bulk-" + seq.incrementAndGet();
        final Batch b = new Batch(id, true, phones.size(), null);
        batches.put(id, b);
        final int delay = phones.size() > 50 ? DELAY_LARGE_MS : DELAY_NORMAL_MS;

        jsCallback("onSmsBulkStart", "{\"total\":" + phones.size() + "}");

        new Thread(() -> {
            for (int i = 0; i < phones.size(); i++) {
                String phone = phones.get(i);
                try {
                    dispatch(b, phone, message);
                } catch (Exception e) {
                    synchronized (b) { b.failed.add(phone); }
                }

                int failedNow;
                synchronized (b) { failedNow = b.failed.size(); }
                int current = i + 1;
                jsCallback("onSmsBulkProgress",
                        "{\"current\":" + current + ",\"total\":" + phones.size()
                                + ",\"sent\":" + (current - failedNow)
                                + ",\"failed\":" + failedNow
                                + ",\"phone\":" + q(phone) + "}");

                if (current < phones.size()) {
                    try { Thread.sleep(delay); } catch (InterruptedException ignored) {}
                }
            }
            synchronized (b) { b.dispatchDone = true; }
            scheduleTimeout(b);
            maybeFinish(b);
        }).start();
    }

    // ─── ارسال یک پیام با sentIntent واقعی (نتیجهٔ واقعی از سیستم می‌آید) ───
    private void dispatch(Batch b, String phone, String message) {
        SmsManager sm = getSmsManager();
        ArrayList<String> parts = sm.divideMessage(message);
        ArrayList<PendingIntent> sentIntents = new ArrayList<>();
        for (int i = 0; i < parts.size(); i++) {
            Intent in = new Intent(actionSent).setPackage(activity.getPackageName());
            in.putExtra("batch", b.id);
            in.putExtra("phone", phone);
            sentIntents.add(PendingIntent.getBroadcast(activity, seq.incrementAndGet(), in,
                    PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_ONE_SHOT));
        }
        synchronized (b) { b.partsExpected += parts.size(); }
        try {
            sm.sendMultipartTextMessage(phone, null, parts, sentIntents, null);
        } catch (RuntimeException e) {
            synchronized (b) { b.partsExpected -= parts.size(); }   // برای این پیام receipt نمی‌آید
            throw e;
        }
    }

    private SmsManager getSmsManager() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return activity.getSystemService(SmsManager.class);
        }
        return SmsManager.getDefault();
    }

    // ─── پایان ارسال ───
    private void maybeFinish(Batch b) {
        boolean fire;
        synchronized (b) {
            fire = b.dispatchDone && b.partsDone >= b.partsExpected && !b.reported;
            if (fire) b.reported = true;
        }
        if (fire) finish(b);
    }

    /** اگر سیستم رسید بعضی بخش‌ها را نداد، بعد از مهلت گزارش نهایی می‌دهیم */
    private void scheduleTimeout(final Batch b) {
        mainHandler.postDelayed(() -> {
            boolean fire;
            synchronized (b) {
                fire = !b.reported;
                if (fire) b.reported = true;
            }
            if (fire) finish(b);
        }, REPORT_TIMEOUT_MS);
    }

    private void finish(Batch b) {
        batches.remove(b.id);
        int failed;
        synchronized (b) { failed = b.failed.size(); }

        if (b.bulk) {
            bulkRunning = false;
            int sent = b.total - failed;
            jsCallback("onSmsBulkComplete",
                    "{\"ok\":" + (sent > 0) + ",\"sent\":" + sent
                            + ",\"failed\":" + failed + ",\"total\":" + b.total + "}");
        } else {
            boolean ok = failed == 0;
            jsCallback("onSmsResult",
                    "{\"ok\":" + ok + ",\"phone\":" + q(b.phone)
                            + (ok ? "" : ",\"error\":\"send_failed\"") + "}");
        }
    }

    // ─── کمکی‌ها ───
    private ArrayList<String> parsePhones(String json) {
        LinkedHashSet<String> set = new LinkedHashSet<>();   // حذف شمارهٔ تکراری
        if (json == null) return new ArrayList<>();
        json = json.trim();
        if (json.startsWith("[")) json = json.substring(1);
        if (json.endsWith("]")) json = json.substring(0, json.length() - 1);
        if (json.isEmpty()) return new ArrayList<>();
        for (String item : json.split(",")) {
            String p = item.replaceAll("\\D", "");
            if (p.length() >= 10) set.add(p);
        }
        return new ArrayList<>(set);
    }

    /** رشتهٔ امن برای JSON/JS (escape کوتیشن، خط جدید و ...) */
    private static String q(String s) {
        return JSONObject.quote(s == null ? "" : s);
    }

    private void jsCallback(final String function, final String jsonArg) {
        if (webView == null) return;
        activity.runOnUiThread(() -> webView.evaluateJavascript(
                "if(window." + function + ")window." + function + "(" + jsonArg + ");", null));
    }
}
