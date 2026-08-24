package io.github.shinkatana0.shelfscan

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.ByteArrayOutputStream

/**
 * HEIC -> JPEG for `app/lib/heic_android.dart`.
 *
 * BitmapFactory has decoded HEIF since API 28, so this needs no dependency:
 * that is the whole reason the Dart side chose a channel over a pub plugin,
 * and it is why nothing in `android/` had to change to add this file.
 */
private const val CHANNEL = "io.github.shinkatana0.shelfscan/heic"

/**
 * Chosen to match WIC's documented default, which the Windows path takes by
 * passing no property bag to the JPEG encoder: the two hosts should not hand
 * the vision stage bytes differing by an unmeasured amount. Nobody has
 * measured what quality costs the spine reads -- if that is ever measured,
 * this is the constant, and the Windows one is a property bag away.
 */
private const val JPEG_QUALITY = 90

fun registerHeicChannel(engine: FlutterEngine) {
    val messenger = engine.dartExecutor.binaryMessenger
    // A background queue rather than the platform thread, for the reason the
    // Windows path uses an isolate: a phone photo takes hundreds of ms and
    // this runs while the user is watching the picker.
    val channel = MethodChannel(
        messenger,
        CHANNEL,
        StandardMethodCodec.INSTANCE,
        messenger.makeBackgroundTaskQueue(),
    )
    channel.setMethodCallHandler { call, result ->
        if (call.method != "toJpeg") {
            result.notImplemented()
            return@setMethodCallHandler
        }
        val heic = call.arguments as? ByteArray
        if (heic == null) {
            result.error("bad-argument", "the decoder was given no bytes", null)
            return@setMethodCallHandler
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            result.error(
                "no-codec",
                "this phone runs Android ${Build.VERSION.RELEASE}, which has " +
                    "no HEIC decoder; Android 9 or later can read it, or " +
                    "convert the file to .jpg or .png first",
                null,
            )
            return@setMethodCallHandler
        }
        try {
            result.success(toJpeg(heic))
        } catch (e: OutOfMemoryError) {
            // Not an Exception, so a bare `catch (e: Exception)` would let it
            // kill the engine instead of rejecting the one photo.
            result.error(
                "too-large",
                "this photo is too large to decode on this phone",
                null,
            )
        } catch (e: Exception) {
            result.error("decode-failed", "Android could not decode this HEIC", null)
        }
    }
}

private fun toJpeg(heic: ByteArray): ByteArray {
    val bitmap: Bitmap = BitmapFactory.decodeByteArray(heic, 0, heic.size)
        ?: throw IllegalArgumentException("not an image this phone can decode")
    try {
        val out = ByteArrayOutputStream(heic.size)
        if (!bitmap.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, out)) {
            throw IllegalStateException("the JPEG encoder refused the image")
        }
        return out.toByteArray()
    } finally {
        bitmap.recycle()
    }
}
