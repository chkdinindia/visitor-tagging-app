package com.chkdin.visitor_tagging

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

/**
 * Forwards barcodes from built-in laser scanners (broadcast / intent output mode)
 * to Flutter over an EventChannel.
 *
 * Scanners in keyboard-wedge mode do not need this; they type into the hidden
 * input field on the scan screen.
 */
class MainActivity : FlutterActivity() {

    private var receiver: BroadcastReceiver? = null
    private var sink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    sink = events
                    registerScanReceiver()
                }

                override fun onCancel(arguments: Any?) {
                    unregisterScanReceiver()
                    sink = null
                }
            }
        )
    }

    private fun registerScanReceiver() {
        if (receiver != null) return
        val scanReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val code = intent?.let { extractBarcode(it) } ?: return
                if (code.isNotBlank()) sink?.success(code.trim())
            }
        }
        val filter = IntentFilter().apply { SCAN_ACTIONS.forEach { addAction(it) } }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(scanReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            registerReceiver(scanReceiver, filter)
        }
        receiver = scanReceiver
    }

    private fun unregisterScanReceiver() {
        receiver?.let {
            try {
                unregisterReceiver(it)
            } catch (e: IllegalArgumentException) {
                // Already unregistered.
            }
        }
        receiver = null
    }

    @Suppress("DEPRECATION")
    private fun extractBarcode(intent: Intent): String? {
        val extras = intent.extras ?: return null
        val length = intent.getIntExtra("length", -1)
        for (key in EXTRA_KEYS) {
            if (!extras.containsKey(key)) continue
            when (val value = extras.get(key)) {
                is String -> if (value.isNotBlank()) return value
                is ByteArray -> {
                    val size = if (length in 1..value.size) length else value.size
                    val text = String(value, 0, size, Charsets.UTF_8)
                    if (text.isNotBlank()) return text
                }
            }
        }
        return null
    }

    override fun onDestroy() {
        unregisterScanReceiver()
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "com.chkdin.visitor_tagging/scanner"

        /** Broadcast actions used by common Android PDA scanners. */
        private val SCAN_ACTIONS = listOf(
            "com.chkdin.visitor_tagging.SCAN",               // Custom (Zebra DataWedge / any configurable scanner)
            "android.intent.ACTION_DECODE_DATA",             // Urovo
            "nlscan.action.SCANNER_RESULT",                  // Newland
            "com.sunmi.scanner.ACTION_DATA_CODE_RECEIVED",   // Sunmi
            "android.intent.action.SCANRESULT",              // iData
            "com.scanner.broadcast",                         // Chainway / generic
            "scan.rcv.message",                              // Chainway (older)
            "com.android.server.scannerservice.broadcast",   // Seuic
            "com.honeywell.scan.broadcast",                  // Honeywell (configurable)
            "android.intent.action.SCANNER_RESULT",          // Generic
            "com.barcode.sendBroadcast",                     // Generic
        )

        /** Extra keys that carry the decoded barcode, in priority order. */
        private val EXTRA_KEYS = listOf(
            "barcode_string",                       // Urovo
            "com.symbol.datawedge.data_string",     // Zebra
            "SCAN_BARCODE1",                        // Newland
            "scannerdata",                          // Seuic
            "data",                                 // Sunmi / Chainway / Honeywell
            "value",                                // iData
            "barcodeData",
            "data_string",
            "decode_data",
            "scan_result",
            "barcode",                              // Urovo / generic (may be bytes)
            "barocode",                             // Chainway older (bytes)
            "BARCODE",
        )
    }
}
