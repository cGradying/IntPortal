# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.
#
# For more details, see
#   http://developer.android.com/guide/developing/tools/proguard.html

# If your project uses WebView with JS, uncomment the following
# and specify the fully qualified class name to the JavaScript interface
# class:
#-keepclassmembers class fqcn.of.javascript.interface.for.webview {
#   public *;
#}

# Uncomment this to preserve the line number information for
# debugging stack traces.
#-keepattributes SourceFile,LineNumberTable

# If you keep the line number information, uncomment this to
# hide the original source file name.
#-renamesourcefileattribute SourceFile
# Tauri's build script writes this rule to proguard-tauri.pro (gitignored), but
# only when its build script reruns. A fresh worktree on a cached cargo target
# never gets the file, R8 strips getPluginManager and the release APK crashes
# at launch. Keep the rule here so release builds never depend on that file.
-keep class ph.intportal.app.TauriActivity {
  public app.tauri.plugin.PluginManager getPluginManager();
}
