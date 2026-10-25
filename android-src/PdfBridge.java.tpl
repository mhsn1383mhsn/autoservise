__PACKAGE__

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.print.PdfPrint;
import android.print.PrintAttributes;
import android.print.PrintDocumentAdapter;
import android.print.PrintManager;
import android.provider.MediaStore;
import android.webkit.JavascriptInterface;
import android.webkit.WebView;

import org.json.JSONObject;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

/**
 * پل PDF/چاپ. در JS با نام «AndroidPdf» ثبت می‌شود.
 *   AndroidPdf.savePdf(fileName)  → PDF از صفحهٔ جاری (با CSS چاپ) ساخته و در Download ذخیره می‌شود
 *   AndroidPdf.print(jobName)     → پنجرهٔ چاپ سیستم (چاپ یا Save as PDF)
 *   AndroidPdf.openFile(uri)      → باز کردن فایل ذخیره‌شده در برنامهٔ PDF خوان
 * نتیجه با window.onPdfSaved({ok,name,uri,where}) یا window.onPdfError(code) برمی‌گردد.
 */
public class PdfBridge {

    private final Activity activity;
    private final WebView webView;
    private volatile boolean busy = false;

    public PdfBridge(Activity activity, WebView webView) {
        this.activity = activity;
        this.webView = webView;
    }

    // A4 با حاشیهٔ ۱۰ میلی‌متر (۴۰۰ میل = ۱۰ میلی‌متر)
    private PrintAttributes pdfAttributes() {
        return new PrintAttributes.Builder()
            .setMediaSize(PrintAttributes.MediaSize.ISO_A4)
            .setResolution(new PrintAttributes.Resolution("pdf", "pdf", 300, 300))
            .setMinMargins(new PrintAttributes.Margins(400, 400, 400, 400))
            .build();
    }

    @JavascriptInterface
    public void savePdf(final String fileName) {
        if (busy) { jsError("busy"); return; }
        busy = true;
        final String name = safeName(fileName);
        activity.runOnUiThread(new Runnable() {
            @Override public void run() {
                try {
                    final File tmp = new File(activity.getCacheDir(), "invoice-tmp.pdf");
                    PrintDocumentAdapter adapter = webView.createPrintDocumentAdapter(name);
                    new PdfPrint(pdfAttributes()).write(adapter, tmp, new PdfPrint.Callback() {
                        @Override public void onSuccess() {
                            new Thread(new Runnable() {
                                @Override public void run() {
                                    try {
                                        String[] res = saveToDownloads(tmp, name);
                                        jsSaved(name, res[0], res[1]);
                                    } catch (Exception e) {
                                        jsError("save_failed");
                                    } finally {
                                        //noinspection ResultOfMethodCallIgnored
                                        tmp.delete();
                                        busy = false;
                                    }
                                }
                            }).start();
                        }
                        @Override public void onFailure(String message) {
                            busy = false;
                            jsError(message);
                        }
                    });
                } catch (Exception e) {
                    busy = false;
                    jsError("exception");
                }
            }
        });
    }

    @JavascriptInterface
    public void print(final String jobName) {
        activity.runOnUiThread(new Runnable() {
            @Override public void run() {
                try {
                    String n = (jobName == null || jobName.isEmpty()) ? "invoice" : jobName;
                    PrintManager pm = (PrintManager) activity.getSystemService(Context.PRINT_SERVICE);
                    pm.print(n, webView.createPrintDocumentAdapter(n), new PrintAttributes.Builder().build());
                } catch (Exception e) {
                    jsError("print_failed");
                }
            }
        });
    }

    @JavascriptInterface
    public void openFile(final String uriString) {
        activity.runOnUiThread(new Runnable() {
            @Override public void run() {
                try {
                    Intent in = new Intent(Intent.ACTION_VIEW);
                    in.setDataAndType(Uri.parse(uriString), "application/pdf");
                    in.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
                    activity.startActivity(in);
                } catch (ActivityNotFoundException e) {
                    jsError("no_viewer");
                } catch (Exception e) {
                    jsError("open_failed");
                }
            }
        });
    }

    /** خروجی: [uri یا رشتهٔ خالی, محل ذخیره] */
    private String[] saveToDownloads(File src, String name) throws IOException {
        if (Build.VERSION.SDK_INT >= 29) {
            ContentResolver r = activity.getContentResolver();
            ContentValues v = new ContentValues();
            v.put(MediaStore.Downloads.DISPLAY_NAME, name);
            v.put(MediaStore.Downloads.MIME_TYPE, "application/pdf");
            v.put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS);
            v.put(MediaStore.Downloads.IS_PENDING, 1);
            Uri uri = r.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, v);
            if (uri == null) throw new IOException("insert failed");
            OutputStream os = r.openOutputStream(uri);
            if (os == null) throw new IOException("stream failed");
            try { copy(src, os); } finally { os.close(); }
            v.clear();
            v.put(MediaStore.Downloads.IS_PENDING, 0);
            r.update(uri, v, null, null);
            return new String[]{uri.toString(), "Download"};
        }
        // اندروید ۹ و پایین‌تر: پوشهٔ اختصاصی برنامه (بدون نیاز به مجوز)
        File dir = activity.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS);
        if (dir == null) dir = activity.getFilesDir();
        //noinspection ResultOfMethodCallIgnored
        dir.mkdirs();
        File out = new File(dir, name);
        java.io.FileOutputStream fos = new java.io.FileOutputStream(out);
        try { copy(src, fos); } finally { fos.close(); }
        return new String[]{"", out.getAbsolutePath()};
    }

    private static void copy(File src, OutputStream os) throws IOException {
        InputStream is = new FileInputStream(src);
        try {
            byte[] buf = new byte[16 * 1024];
            int n;
            while ((n = is.read(buf)) > 0) os.write(buf, 0, n);
        } finally { is.close(); }
    }

    private static String safeName(String s) {
        if (s == null) s = "";
        s = s.replaceAll("[^A-Za-z0-9._-]", "_");
        if (s.isEmpty()) s = "invoice";
        if (!s.toLowerCase().endsWith(".pdf")) s += ".pdf";
        return s;
    }

    private void jsSaved(String name, String uri, String where) {
        String json = "{\"ok\":true,\"name\":" + q(name) + ",\"uri\":" + q(uri) + ",\"where\":" + q(where) + "}";
        js("onPdfSaved", json);
    }

    private void jsError(String code) { js("onPdfError", q(code)); }

    private static String q(String s) { return JSONObject.quote(s == null ? "" : s); }

    private void js(final String fn, final String arg) {
        if (webView == null) return;
        activity.runOnUiThread(new Runnable() {
            @Override public void run() {
                webView.evaluateJavascript("if(window." + fn + ")window." + fn + "(" + arg + ");", null);
            }
        });
    }
}
