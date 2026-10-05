package ph.intportal.app

import android.os.Bundle
import android.webkit.JavascriptInterface
import android.webkit.WebView
import androidx.activity.enableEdgeToEdge
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat

class MainActivity : TauriActivity() {
  @Volatile private var safe = "0 0"

  override fun onCreate(savedInstanceState: Bundle?) {
    enableEdgeToEdge()
    super.onCreate(savedInstanceState)
  }

  // The bridge for src/lib/bars.ts. The page reports what sits under the
  // system bars so their icons stay readable; it reads the bars' heights
  // from here because older WebViews leave env(safe-area-inset-*) at 0.
  override fun onWebViewCreate(webView: WebView) {
    webView.addJavascriptInterface(object {
      @JavascriptInterface
      fun bars(topDark: Boolean, bottomDark: Boolean) = runOnUiThread {
        WindowCompat.getInsetsController(window, window.decorView).apply {
          isAppearanceLightStatusBars = !topDark
          isAppearanceLightNavigationBars = !bottomDark
        }
      }

      /** Back with nothing left to close: off to the background, like Home. */
      @JavascriptInterface
      fun leave() = runOnUiThread { moveTaskToBack(true) }

      /** "top bottom" in CSS pixels. */
      @JavascriptInterface
      fun insets() = safe
    }, "IntPortalAndroid")
    ViewCompat.setOnApplyWindowInsetsListener(webView) { view, insets ->
      val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
      val dp = resources.displayMetrics.density
      safe = "${bars.top / dp} ${bars.bottom / dp}"
      view.post { (view as WebView).evaluateJavascript("window.dispatchEvent(new Event('insets'))", null) }
      ViewCompat.onApplyWindowInsets(view, insets)
    }
  }
}
