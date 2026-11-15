package ph.intportal.camera

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.net.Uri
import android.provider.MediaStore
import androidx.activity.result.ActivityResult
import androidx.core.content.FileProvider
import androidx.exifinterface.media.ExifInterface
import app.tauri.annotation.ActivityCallback
import app.tauri.annotation.Command
import app.tauri.annotation.InvokeArg
import app.tauri.annotation.TauriPlugin
import app.tauri.plugin.Invoke
import app.tauri.plugin.JSArray
import app.tauri.plugin.JSObject
import app.tauri.plugin.Plugin
import com.google.android.gms.common.api.OptionalModuleApi
import com.google.android.gms.common.moduleinstall.InstallStatusListener
import com.google.android.gms.common.moduleinstall.ModuleInstall
import com.google.android.gms.common.moduleinstall.ModuleInstallRequest
import com.google.android.gms.common.moduleinstall.ModuleInstallStatusUpdate.InstallState
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.math.max

@InvokeArg
class ReadArgs {
    var text: Boolean = false
    var qr: Boolean = false
}

@InvokeArg
class CaptureArgs {
    var source: String = "camera"
    var read: ReadArgs? = null
    var saveTo: String? = null
}

/** The scanner's models aren't on the phone and couldn't be downloaded. */
private class NoScanner : Exception()

/** Longest side of a kept photo, in pixels. */
private const val MAX_SIDE = 1600

/**
 * One photo from the phone's camera app or the system picker, read on the
 * phone by ML Kit. The camera's temporary file is always deleted; a photo is
 * kept only as a JPEG in `saveTo`. The manifest turns app backups off.
 */
@TauriPlugin
class CameraPlugin(private val activity: Activity) : Plugin(activity) {
    private val shot get() = File(activity.cacheDir, "camera/shot.jpg")

    @Command
    fun capture(invoke: Invoke) {
        val args = invoke.parseArgs(CaptureArgs::class.java)
        if (args.saveTo != null && !insideAppData(args.saveTo!!)) return invoke.reject("bad_folder")
        try {
            if (args.source == "library") {
                val pick = Intent(Intent.ACTION_GET_CONTENT).setType("image/*").addCategory(Intent.CATEGORY_OPENABLE)
                startActivityForResult(invoke, pick, "picked")
            } else {
                shot.parentFile?.mkdirs()
                val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.camera.files", shot)
                val take = Intent(MediaStore.ACTION_IMAGE_CAPTURE).putExtra(MediaStore.EXTRA_OUTPUT, uri).addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                startActivityForResult(invoke, take, "taken")
            }
        } catch (_: ActivityNotFoundException) {
            invoke.reject("no_camera")
        }
    }

    @ActivityCallback
    fun taken(invoke: Invoke, result: ActivityResult) {
        if (result.resultCode != Activity.RESULT_OK) {
            shot.delete()
            return cancelled(invoke)
        }
        handle(invoke, Uri.fromFile(shot))
    }

    @ActivityCallback
    fun picked(invoke: Invoke, result: ActivityResult) {
        val uri = result.data?.data
        if (result.resultCode != Activity.RESULT_OK || uri == null) return cancelled(invoke)
        handle(invoke, uri)
    }

    private fun cancelled(invoke: Invoke) = invoke.resolve(JSObject().put("cancelled", true))

    private fun handle(invoke: Invoke, uri: Uri) {
        val args = invoke.parseArgs(CaptureArgs::class.java)
        Thread {
            try {
                val out = JSObject().put("cancelled", false)
                read(uri, args.read, out)
                args.saveTo?.let { save(uri, it, out) }
                invoke.resolve(out)
            } catch (_: NoScanner) {
                invoke.reject("no_scanner")
            } catch (e: IOException) {
                invoke.reject(if (e.message?.contains("ENOSPC") == true) "no_space" else "save_failed")
            } catch (_: Exception) {
                invoke.reject("bad_photo")
            } finally {
                shot.delete()
            }
        }.start()
    }

    private fun read(uri: Uri, wanted: ReadArgs?, out: JSObject) {
        val what = wanted ?: return
        if (!what.text && !what.qr) return
        val image = InputImage.fromFilePath(activity, uri)
        val text = if (what.text) TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS) else null
        val qr = if (what.qr) BarcodeScanning.getClient(BarcodeScannerOptions.Builder().setBarcodeFormats(Barcode.FORMAT_QR_CODE).build()) else null
        try {
            downloaded(listOfNotNull(text, qr))
            text?.let { out.put("text", Tasks.await(it.process(image)).text) }
            qr?.let { c ->
                val found = JSArray()
                Tasks.await(c.process(image)).mapNotNull { it.rawValue }.forEach { found.put(it) }
                out.put("qr", found)
            }
        } finally {
            text?.close()
            qr?.close()
        }
    }

    /**
     * Waits for Play services to have the scanner's models, downloading them
     * the first time (Play normally installs them with the app). The web view
     * hears a `scanner` event so it can say "Downloading the scanner…".
     */
    private fun downloaded(apis: List<OptionalModuleApi>) {
        val installer = ModuleInstall.getClient(activity)
        try {
            if (Tasks.await(installer.areModulesAvailable(*apis.toTypedArray())).areModulesAvailable()) return
        } catch (_: Exception) {
            throw NoScanner() // no Play services on this phone
        }
        trigger("scanner", JSObject().put("state", "downloading"))
        val done = CountDownLatch(1)
        var ok = false
        val listener = InstallStatusListener { u ->
            when (u.installState) {
                InstallState.STATE_COMPLETED -> { ok = true; done.countDown() }
                InstallState.STATE_FAILED, InstallState.STATE_CANCELED -> done.countDown()
                else -> {}
            }
        }
        val request = ModuleInstallRequest.newBuilder().apply { apis.forEach { addApi(it) } }.setListener(listener).build()
        try {
            if (Tasks.await(installer.installModules(request)).areModulesAlreadyInstalled()) return
            if (!done.await(3, TimeUnit.MINUTES) || !ok) throw NoScanner()
        } catch (e: NoScanner) {
            throw e
        } catch (_: Exception) {
            throw NoScanner()
        } finally {
            installer.unregisterListener(listener)
        }
    }

    /** A JPEG in `folder`, upright and at most MAX_SIDE on its long side. */
    private fun save(uri: Uri, folder: String, out: JSObject) {
        val resolver = activity.contentResolver
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        resolver.openInputStream(uri).use { BitmapFactory.decodeStream(it, null, bounds) }
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= MAX_SIDE) sample *= 2
        val decoded = resolver.openInputStream(uri).use { BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample }) }
            ?: throw IllegalArgumentException("not an image")
        val degrees = resolver.openInputStream(uri).use { s -> s?.let { ExifInterface(it).rotationDegrees } ?: 0 }
        val scale = minOf(1f, MAX_SIDE.toFloat() / max(decoded.width, decoded.height))
        val matrix = Matrix().apply {
            postScale(scale, scale)
            postRotate(degrees.toFloat())
        }
        val upright = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
        val dir = File(folder).apply { mkdirs() }
        val file = File(dir, "${UUID.randomUUID()}.jpg")
        FileOutputStream(file).use { upright.compress(Bitmap.CompressFormat.JPEG, 85, it) }
        out.put("path", file.path).put("width", upright.width).put("height", upright.height)
    }

    private fun insideAppData(folder: String): Boolean {
        val root = File(activity.applicationInfo.dataDir).canonicalPath
        val path = File(folder).canonicalPath
        return path == root || path.startsWith("$root/")
    }
}
