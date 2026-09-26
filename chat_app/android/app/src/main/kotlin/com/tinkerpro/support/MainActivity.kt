package com.tinkerpro.support

import android.content.Intent
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    private val channelName = "com.tinkerpro.support/chat_bubble"
    private val linkChannelName = "com.tinkerpro.support/app_link"
    private var bubbleChannel: MethodChannel? = null
    private var linkChannel: MethodChannel? = null
    private var pendingLink: Map<String, Any?>? = null
    private var dartReady = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bubbleChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        linkChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, linkChannelName)
        linkChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "consumeInitialLink" -> {
                    dartReady = true
                    val link = pendingLink
                    pendingLink = null
                    result.success(link)
                }
                else -> result.notImplemented()
            }
        }
        handleLinkIntent(intent)
        forwardChatIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleLinkIntent(intent)
        forwardChatIntent(intent)
    }

    private fun handleLinkIntent(intent: Intent?) {
        val data = intent?.data ?: return
        if (data.scheme != "tinkerprochat") return
        val handoff = data.getQueryParameter("handoff").orEmpty()
        if (handoff.isEmpty()) return
        val payload = mapOf(
            "handoff" to handoff,
            "conversationId" to (data.getQueryParameter("conversation")?.toIntOrNull() ?: 0),
        )
        if (dartReady) {
            linkChannel?.invokeMethod("onLink", payload)
        } else {
            pendingLink = payload
        }
    }

    private fun forwardChatIntent(intent: Intent?) {
        var convId = intent?.getIntExtra("chat_conversation_id", 0) ?: 0
        if (convId <= 0) {
            val data = intent?.data
            if (data != null && data.scheme == "tinkerprochat") {
                convId = data.getQueryParameter("conversation")?.toIntOrNull() ?: 0
            }
        }
        if (convId <= 0) return
        bubbleChannel?.invokeMethod(
            "openConversation",
            mapOf("conversationId" to convId),
        )
    }
}
