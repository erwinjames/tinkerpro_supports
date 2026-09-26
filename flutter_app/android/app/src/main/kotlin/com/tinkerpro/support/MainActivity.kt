package com.tinkerpro.support

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    private val channelName = "com.tinkerpro.support/chat_bubble"
    private val chatAppChannelName = "com.tinkerpro.support/chat_app"
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

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            chatAppChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isTrusted" -> result.success(chatAppIsTrusted())
                "open" -> {
                    val uri = call.argument<String>("uri") ?: ""
                    result.success(openChatApp(uri))
                }
                else -> result.notImplemented()
            }
        }

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
        pendingChannel?.invokeMethod(
            "openConversation",
            mapOf("conversationId" to convId),
        )
    }

    private fun chatAppIsTrusted(): Boolean {
        return try {
            packageManager.getPackageInfo(CHAT_APP_PACKAGE, 0)
            packageManager.checkSignatures(packageName, CHAT_APP_PACKAGE) ==
                PackageManager.SIGNATURE_MATCH
        } catch (e: Throwable) {
            false
        }
    }

    private fun openChatApp(uri: String): Boolean {
        if (uri.isEmpty() || !chatAppIsTrusted()) return false
        return try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(uri)).apply {
                setPackage(CHAT_APP_PACKAGE)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (e: Throwable) {
            false
        }
    }

    companion object {
        private const val CHAT_APP_PACKAGE = "com.tinkerpro.chat"
    }
}
