package com.aureon.storage

import com.aureon.storage.generated.AureonStorageHostApi
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger

/**
 * Registers the typed Pigeon bridge for each attached FlutterEngine.
 * The Room database is application-scoped; the message handler is engine-scoped.
 */
class AureonStoragePlugin : FlutterPlugin {
    private var attachedMessenger: BinaryMessenger? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        check(attachedMessenger == null) { "AUREON storage plugin is already attached" }

        val database = AureonStorageDatabase.get(binding.applicationContext)
        val repository = TransferCheckpointRepository(database.transferJobDao())
        AureonStorageHostApi.setUp(
            binding.binaryMessenger,
            AureonStorageHostApiImpl(repository)
        )
        attachedMessenger = binding.binaryMessenger
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val messenger = attachedMessenger ?: return
        AureonStorageHostApi.setUp(messenger, null)
        attachedMessenger = null
    }
}
