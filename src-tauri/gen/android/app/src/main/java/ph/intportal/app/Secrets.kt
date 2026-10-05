package ph.intportal.app

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.annotation.Keep
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Android's keychain for the Rust side (`keychain` in lib.rs calls these
 * through JNI): each value is sealed with an AES-GCM key that never leaves
 * the Android Keystore, and the sealed bytes sit in app-private prefs.
 */
@Keep
object Secrets {
    private const val ALIAS = "intportal.secrets"
    private const val IV = 12

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(
                KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .build(),
            )
        }.generateKey()
    }

    private fun prefs(context: Context) = context.getSharedPreferences("secrets", Context.MODE_PRIVATE)

    /** Null when nothing is saved under `name`; throws when it can't be opened. */
    @JvmStatic
    fun get(context: Context, name: String): String? {
        val sealed = Base64.decode(prefs(context).getString(name, null) ?: return null, Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, sealed, 0, IV))
        return String(cipher.doFinal(sealed, IV, sealed.size - IV), Charsets.UTF_8)
    }

    @JvmStatic
    fun set(context: Context, name: String, value: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val sealed = cipher.iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        check(prefs(context).edit().putString(name, Base64.encodeToString(sealed, Base64.NO_WRAP)).commit()) { "Couldn't save $name." }
    }

    @JvmStatic
    fun delete(context: Context, name: String) {
        prefs(context).edit().remove(name).commit()
    }
}
