package android.print;

import android.os.CancellationSignal;
import android.os.ParcelFileDescriptor;

import java.io.File;
import java.io.IOException;

/**
 * نوشتن محتوای WebView در فایل PDF بدون نمایش پنجرهٔ چاپ.
 * سازندهٔ LayoutResultCallback / WriteResultCallback فقط داخل پکیج android.print در دسترس است،
 * به همین دلیل این کلاس عمداً در همین پکیج قرار دارد.
 */
public class PdfPrint {

    public interface Callback {
        void onSuccess();
        void onFailure(String message);
    }

    private final PrintAttributes attributes;

    public PdfPrint(PrintAttributes attributes) {
        this.attributes = attributes;
    }

    /** باید روی UI thread صدا زده شود. نتیجه روی همان thread برمی‌گردد. */
    public void write(final PrintDocumentAdapter adapter, final File file, final Callback cb) {
        try {
            adapter.onStart();
            adapter.onLayout(null, attributes, new CancellationSignal(),
                new PrintDocumentAdapter.LayoutResultCallback() {
                    @Override
                    public void onLayoutFinished(PrintDocumentInfo info, boolean changed) {
                        final ParcelFileDescriptor fd;
                        try {
                            fd = ParcelFileDescriptor.open(file,
                                ParcelFileDescriptor.MODE_READ_WRITE
                                    | ParcelFileDescriptor.MODE_CREATE
                                    | ParcelFileDescriptor.MODE_TRUNCATE);
                        } catch (IOException e) {
                            adapter.onFinish();
                            cb.onFailure("open_failed");
                            return;
                        }
                        adapter.onWrite(new PageRange[]{PageRange.ALL_PAGES}, fd,
                            new CancellationSignal(),
                            new PrintDocumentAdapter.WriteResultCallback() {
                                @Override
                                public void onWriteFinished(PageRange[] pages) {
                                    close(fd);
                                    adapter.onFinish();
                                    cb.onSuccess();
                                }
                                @Override
                                public void onWriteFailed(CharSequence error) {
                                    close(fd);
                                    adapter.onFinish();
                                    cb.onFailure("write_failed");
                                }
                                @Override
                                public void onWriteCancelled() {
                                    close(fd);
                                    adapter.onFinish();
                                    cb.onFailure("cancelled");
                                }
                            });
                    }
                    @Override
                    public void onLayoutFailed(CharSequence error) {
                        adapter.onFinish();
                        cb.onFailure("layout_failed");
                    }
                    @Override
                    public void onLayoutCancelled() {
                        adapter.onFinish();
                        cb.onFailure("cancelled");
                    }
                }, null);
        } catch (Exception e) {
            cb.onFailure("exception");
        }
    }

    private static void close(ParcelFileDescriptor fd) {
        try { fd.close(); } catch (IOException ignored) {}
    }
}
