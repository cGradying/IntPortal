package ph.intportal.camera

import androidx.core.content.FileProvider

/** Its own class so the manifest merger keeps it apart from the app's FileProvider. */
class CameraFileProvider : FileProvider()
