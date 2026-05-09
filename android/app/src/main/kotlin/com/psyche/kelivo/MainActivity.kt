package com.psyche.kelivo

import android.app.Activity
import android.content.ActivityNotFoundException
import android.net.Uri
import android.content.Intent
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {
    private companion object {
        const val CREATE_DOCUMENT_REQUEST_CODE = 4107
        const val OPEN_DIRECTORY_REQUEST_CODE = 4108
    }

    private val processTextChannelName = "app.process_text"
    private val fileSaveChannelName = "app.file_save"
    private var processTextChannel: MethodChannel? = null
    private var fileSaveChannel: MethodChannel? = null
    private var pendingProcessText: String? = null
    private var pendingSaveResult: MethodChannel.Result? = null
    private var pendingSaveSourcePath: String? = null
    private var pendingDirectoryResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        processTextChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, processTextChannelName)
        processTextChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialText" -> {
                    val text = pendingProcessText ?: extractProcessText(intent)
                    pendingProcessText = null
                    result.success(text)
                }
                else -> result.notImplemented()
            }
        }
        fileSaveChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, fileSaveChannelName)
        fileSaveChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "saveFileFromPath" -> handleSaveFileFromPath(call.arguments, result)
                "pickPersistableDirectory" -> handlePickPersistableDirectory(result)
                "writeFileToPersistableDirectory" -> handleWriteFileToPersistableDirectory(call.arguments, result)
                "releasePersistableDirectoryPermission" -> handleReleasePersistableDirectoryPermission(call.arguments, result)
                else -> result.notImplemented()
            }
        }
        pendingProcessText = extractProcessText(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val text = extractProcessText(intent) ?: return
        val ch = processTextChannel
        if (ch != null) {
            ch.invokeMethod("onProcessText", text)
        } else {
            pendingProcessText = text
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != CREATE_DOCUMENT_REQUEST_CODE) {
            if (requestCode == OPEN_DIRECTORY_REQUEST_CODE) {
                handleDirectoryDestination(if (resultCode == Activity.RESULT_OK) data else null)
            }
            return
        }

        val destUri = if (resultCode == Activity.RESULT_OK) data?.data else null
        handleSaveDestination(destUri)
    }

    private fun extractProcessText(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_PROCESS_TEXT) return null
        val text = intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
        return text?.trim()?.takeIf { it.isNotEmpty() }
    }

    private fun handleSaveFileFromPath(arguments: Any?, result: MethodChannel.Result) {
        if (pendingSaveResult != null) {
            result.error("busy", "Another save operation is already in progress.", null)
            return
        }

        val args = arguments as? Map<*, *>
        val rawSourcePath = args?.get("sourcePath")?.toString()?.trim().orEmpty()
        if (rawSourcePath.isEmpty()) {
            result.error("invalid_args", "Missing sourcePath.", null)
            return
        }

        val sourceFile = File(rawSourcePath)
        if (!sourceFile.exists() || !sourceFile.isFile) {
            result.error("not_found", "Source file does not exist.", null)
            return
        }

        val suggestedFileName = args?.get("fileName")?.toString()?.trim().takeUnless { it.isNullOrEmpty() }
            ?: sourceFile.name

        pendingSaveResult = result
        pendingSaveSourcePath = sourceFile.absolutePath

        try {
            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/zip"
                putExtra(Intent.EXTRA_TITLE, suggestedFileName)
            }
            startActivityForResult(intent, CREATE_DOCUMENT_REQUEST_CODE)
        } catch (e: ActivityNotFoundException) {
            pendingSaveResult = null
            pendingSaveSourcePath = null
            result.error("launch_failed", e.message, null)
        }
    }

    private fun handlePickPersistableDirectory(result: MethodChannel.Result) {
        if (pendingDirectoryResult != null) {
            result.error("busy", "Another directory selection is already in progress.", null)
            return
        }

        pendingDirectoryResult = result
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
            }
            startActivityForResult(intent, OPEN_DIRECTORY_REQUEST_CODE)
        } catch (e: ActivityNotFoundException) {
            pendingDirectoryResult = null
            result.error("launch_failed", e.message, null)
        }
    }

    private fun handleDirectoryDestination(data: Intent?) {
        val result = pendingDirectoryResult ?: return
        val uri = data?.data

        if (uri == null) {
            pendingDirectoryResult = null
            result.success(null)
            return
        }

        try {
            val flags = data.flags and (
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
            contentResolver.takePersistableUriPermission(uri, flags)
            pendingDirectoryResult = null
            result.success(uri.toString())
        } catch (e: Exception) {
            pendingDirectoryResult = null
            result.error("permission_failed", e.message, null)
        }
    }

    private fun handleWriteFileToPersistableDirectory(arguments: Any?, result: MethodChannel.Result) {
        val args = arguments as? Map<*, *>
        val rawDirectoryUri = args?.get("directoryUri")?.toString()?.trim().orEmpty()
        val rawSourcePath = args?.get("sourcePath")?.toString()?.trim().orEmpty()
        val fileName = args?.get("fileName")?.toString()?.trim().orEmpty()

        if (rawDirectoryUri.isEmpty() || rawSourcePath.isEmpty() || fileName.isEmpty()) {
            result.error("invalid_args", "Missing directoryUri, sourcePath, or fileName.", null)
            return
        }

        val sourceFile = File(rawSourcePath)
        if (!sourceFile.exists() || !sourceFile.isFile) {
            result.error("not_found", "Source file does not exist.", null)
            return
        }

        val directoryUri = Uri.parse(rawDirectoryUri)
        val directory = DocumentFile.fromTreeUri(this, directoryUri)
        if (directory == null || !directory.exists() || !directory.isDirectory || !directory.canWrite()) {
            result.error("invalid_directory", "Backup directory is not writable.", null)
            return
        }

        Thread {
            try {
                val existing = directory.findFile(fileName)
                if (existing != null && existing.exists()) {
                    if (!existing.delete()) {
                        throw IllegalStateException("Unable to replace existing backup file.")
                    }
                }

                val target = directory.createFile("application/zip", fileName)
                    ?: throw IllegalStateException("Unable to create backup file.")
                contentResolver.openOutputStream(target.uri, "w")?.use { outputStream ->
                    FileInputStream(sourceFile).use { inputStream ->
                        inputStream.copyTo(outputStream, DEFAULT_BUFFER_SIZE)
                    }
                } ?: throw IllegalStateException("Unable to open backup output stream.")

                runOnUiThread {
                    result.success(true)
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("write_failed", e.message, null)
                }
            }
        }.start()
    }

    private fun handleReleasePersistableDirectoryPermission(arguments: Any?, result: MethodChannel.Result) {
        val args = arguments as? Map<*, *>
        val rawDirectoryUri = args?.get("directoryUri")?.toString()?.trim().orEmpty()
        if (rawDirectoryUri.isEmpty()) {
            result.success(false)
            return
        }

        try {
            contentResolver.releasePersistableUriPermission(
                Uri.parse(rawDirectoryUri),
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }
    }

    private fun handleSaveDestination(destUri: Uri?) {
        val result = pendingSaveResult ?: return
        val sourcePath = pendingSaveSourcePath

        if (destUri == null || sourcePath.isNullOrBlank()) {
            pendingSaveResult = null
            pendingSaveSourcePath = null
            result.success(false)
            return
        }

        Thread {
            try {
                contentResolver.openOutputStream(destUri)?.use { outputStream ->
                    FileInputStream(File(sourcePath)).use { inputStream ->
                        inputStream.copyTo(outputStream, DEFAULT_BUFFER_SIZE)
                    }
                } ?: throw IllegalStateException("Unable to open destination stream.")

                runOnUiThread {
                    pendingSaveResult = null
                    pendingSaveSourcePath = null
                    result.success(true)
                }
            } catch (e: Exception) {
                runOnUiThread {
                    pendingSaveResult = null
                    pendingSaveSourcePath = null
                    result.error("save_failed", e.message, null)
                }
            }
        }.start()
    }
}
