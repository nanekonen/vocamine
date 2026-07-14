package com.example.vacamine

import android.app.Activity
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var pendingScanResult: MethodChannel.Result? = null

    private val scannerLauncher = registerForActivityResult(
        ActivityResultContracts.StartIntentSenderForResult(),
    ) { activityResult ->
        val callback = pendingScanResult ?: return@registerForActivityResult
        pendingScanResult = null
        if (activityResult.resultCode != Activity.RESULT_OK) {
            callback.success(emptyList<ByteArray>())
            return@registerForActivityResult
        }

        try {
            val scanResult = GmsDocumentScanningResult.fromActivityResultIntent(
                activityResult.data,
            )
            val pages = scanResult?.pages.orEmpty().mapNotNull { page ->
                contentResolver.openInputStream(page.imageUri)?.use { it.readBytes() }
            }
            callback.success(pages)
        } catch (error: Exception) {
            callback.error("scan_read_failed", error.message, null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "glossalyze/document_scanner",
        ).setMethodCallHandler { call, result ->
            if (call.method != "scanDocument") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (pendingScanResult != null) {
                result.error("scan_in_progress", "書類スキャンを実行中です", null)
                return@setMethodCallHandler
            }

            pendingScanResult = result
            val options = GmsDocumentScannerOptions.Builder()
                .setGalleryImportAllowed(false)
                .setPageLimit(20)
                .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG)
                .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL)
                .build()
            GmsDocumentScanning.getClient(options)
                .getStartScanIntent(this)
                .addOnSuccessListener { intentSender ->
                    scannerLauncher.launch(IntentSenderRequest.Builder(intentSender).build())
                }
                .addOnFailureListener { error ->
                    pendingScanResult = null
                    result.error("scan_start_failed", error.message, null)
                }
        }
    }
}
