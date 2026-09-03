package com.tinkerpro.support

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts a single MethodChannel ("com.tinkerpro.support/chat_bubble") that
 * Flutter calls into for chat-head notifications. Also reads the
 * `chat_conversation_id` intent extra (set by ChatBubble's PendingIntent)
 * so taps on a bubble or banner navigate to the right thread.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "com.tinkerpro.support/chat_bubble"
    private var pendingChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        )
        pendingChannel = channel
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "show" -> {
                        val convId = call.argument<Int>("conversationId") ?: 0
                        val sender = call.argument<String>("senderName") ?: "Someone"
                        val senderId = call.argument<Int>("senderId") ?: 0
                        val body = call.argument<String>("body") ?: ""
                        if (convId > 0) {
                            ChatBubble.show(
                                applicationContext,
                                conversationId = convId,
                                senderName = sender,
                                senderId = senderId,
                                body = body,
                            )
                        }
                        result.success(true)
                    }
                    "cancel" -> {
                        val convId = call.argument<Int>("conversationId") ?: 0
                        if (convId > 0) {
                            ChatBubble.cancel(applicationContext, convId)
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Throwable) {
                result.error("CHAT_BUBBLE_ERROR", e.message, null)
            }
        }

        // Drain any cold-start intent (e.g. user tapped a bubble while the
        // app was killed). For warm taps we go through onNewIntent.
        forwardChatIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        forwardChatIntent(intent)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }

    private fun forwardChatIntent(intent: Intent?) {
        val convId = intent?.getIntExtra("chat_conversation_id", 0) ?: 0
        if (convId <= 0) return
        // Push to Flutter via the same channel; Flutter side dedupes if
        // it's already showing this thread.
        pendingChannel?.invokeMethod(
            "openConversation",
            mapOf("conversationId" to convId),
        )
    }
}
