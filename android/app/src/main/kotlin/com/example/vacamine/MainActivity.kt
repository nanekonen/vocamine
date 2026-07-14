package com.example.vacamine

import android.app.Activity
import android.speech.tts.TextToSpeech
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterFragmentActivity() {
    private var pendingScanResult: MethodChannel.Result? = null
    private var textToSpeech: TextToSpeech? = null
    private var ttsReady = false
    private val pendingSpeech = mutableListOf<Pair<String, MethodChannel.Result>>()

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
        configureTextToSpeech(flutterEngine)
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

    private fun configureTextToSpeech(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "glossalyze/text_to_speech",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "speak" -> {
                    val text = call.argument<String>("text")?.trim().orEmpty()
                    if (text.isEmpty()) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    if (ttsReady) {
                        speakText(text, result)
                    } else {
                        pendingSpeech.add(text to result)
                        ensureTextToSpeech()
                    }
                }
                "stop" -> {
                    textToSpeech?.stop()
                    pendingSpeech.forEach { (_, callback) -> callback.success(null) }
                    pendingSpeech.clear()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun ensureTextToSpeech() {
        if (textToSpeech != null) return
        textToSpeech = TextToSpeech(this) { status ->
            if (status == TextToSpeech.SUCCESS) {
                val engine = textToSpeech
                val languageResult = engine?.setLanguage(Locale.US)
                if (languageResult == TextToSpeech.LANG_MISSING_DATA ||
                    languageResult == TextToSpeech.LANG_NOT_SUPPORTED
                ) {
                    failPendingSpeech("英語の読み上げ音声が端末にありません")
                    return@TextToSpeech
                }
                engine?.setSpeechRate(0.9f)
                ttsReady = true
                val queued = pendingSpeech.toList()
                pendingSpeech.clear()
                queued.forEach { (text, callback) -> speakText(text, callback) }
            } else {
                failPendingSpeech("端末の読み上げ機能を初期化できませんでした")
            }
        }
    }

    private fun speakText(text: String, result: MethodChannel.Result) {
        val status = textToSpeech?.speak(
            text,
            TextToSpeech.QUEUE_FLUSH,
            null,
            "glossalyze-${System.currentTimeMillis()}",
        )
        if (status == TextToSpeech.SUCCESS) {
            result.success(null)
        } else {
            result.error("tts_failed", "読み上げを開始できませんでした", null)
        }
    }

    private fun failPendingSpeech(message: String) {
        val queued = pendingSpeech.toList()
        pendingSpeech.clear()
        queued.forEach { (_, callback) ->
            callback.error("tts_unavailable", message, null)
        }
        textToSpeech?.shutdown()
        textToSpeech = null
        ttsReady = false
    }

    override fun onDestroy() {
        textToSpeech?.stop()
        textToSpeech?.shutdown()
        textToSpeech = null
        super.onDestroy()
    }
}
