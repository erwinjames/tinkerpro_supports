package com.tinkerpro.support

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.Person
import androidx.core.content.LocusIdCompat
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat

/**
 * Builds Messenger-style chat-bubble notifications.
 *
 * Android 11+ floats a chat-head bubble when:
 *   1. The notification uses NotificationCompat.MessagingStyle, AND
 *   2. It carries BubbleMetadata pointing at a documentLaunchMode-eligible activity, AND
 *   3. It's tied to a long-lived ShortcutInfoCompat for the conversation.
 *
 * On Android 10 and below (or when the user has bubbles disabled), the
 * MessagingStyle notification still renders correctly — it just shows in
 * the system tray instead of floating.
 *
 * The shortcut id is `chat-conv-{conversationId}` so the system can
 * dedupe / reuse the shortcut across bubble updates for the same thread.
 */
object ChatBubble {

    private const val CHANNEL_ID = "tinkerpro_chat"
    private const val CHANNEL_NAME = "TinkerPro Chat"
    private const val SHORTCUT_CATEGORY = "com.tinkerpro.support.category.CHAT"

    fun show(
        context: Context,
        conversationId: Int,
        senderName: String,
        senderId: Int,
        body: String,
    ) {
        ensureChannel(context)
        val shortcutId = "chat-conv-$conversationId"
        publishShortcut(context, shortcutId, conversationId, senderName)

        val sender = Person.Builder()
            .setKey(senderId.toString())
            .setName(senderName)
            .setImportant(true)
            .build()

        // The intent that opens when the user taps either the bubble or
        // the notification body. MainActivity reads the extras and tells
        // Flutter to navigate to the thread.
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            putExtra("chat_conversation_id", conversationId)
            // documentLaunchMode + new task so the system can host the
            // activity inside a bubble window.
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pi = PendingIntent.getActivity(
            context,
            conversationId,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        )

        val style = NotificationCompat.MessagingStyle(
            Person.Builder().setName("You").build(),
        ).addMessage(
            NotificationCompat.MessagingStyle.Message(
                body,
                System.currentTimeMillis(),
                sender,
            ),
        )

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setStyle(style)
            .setShortcutId(shortcutId)
            .setLocusId(LocusIdCompat(shortcutId))
            .addPerson(sender)
            .setContentIntent(pi)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setShowWhen(true)
            .setAutoCancel(true)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // The bubble icon must be renderable as a small circle. The
            // adaptive-icon XML at @mipmap/ic_launcher fails this on some
            // OEMs (Xiaomi/HyperOS in particular) and the bubble silently
            // falls back to "no bubble". Using the static foreground PNG
            // (a real bitmap) is more compatible.
            val bubbleIcon = IconCompat.createWithResource(
                context,
                R.drawable.ic_launcher_foreground,
            )
            val bubbleData = NotificationCompat.BubbleMetadata.Builder(pi, bubbleIcon)
                .setDesiredHeight(600)
                .setAutoExpandBubble(false)
                .setSuppressNotification(false)
                .build()
            builder.bubbleMetadata = bubbleData
        }

        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(conversationId, builder.build())
    }

    /**
     * Long-lived dynamic shortcut. Required to make a notification
     * eligible for the Bubbles API. Without it the system either
     * silently drops the bubble metadata (Android 11) or the post-30
     * bubble policy refuses to float the notification.
     */
    private fun publishShortcut(
        context: Context,
        shortcutId: String,
        conversationId: Int,
        senderName: String,
    ) {
        val openIntent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            putExtra("chat_conversation_id", conversationId)
        }

        val person = Person.Builder()
            .setKey(shortcutId)
            .setName(senderName)
            .build()

        val shortcut = ShortcutInfoCompat.Builder(context, shortcutId)
            .setLongLived(true)
            .setShortLabel(senderName)
            .setLongLabel(senderName)
            // Static PNG, not the adaptive-icon XML — see bubble-icon
            // comment above for why.
            .setIcon(IconCompat.createWithResource(context, R.drawable.ic_launcher_foreground))
            .setIntent(openIntent)
            .setLocusId(LocusIdCompat(shortcutId))
            .setCategories(setOf(SHORTCUT_CATEGORY))
            .setPerson(person)
            .build()

        try {
            ShortcutManagerCompat.pushDynamicShortcut(context, shortcut)
        } catch (_: Throwable) {
            // Some OEMs throttle shortcut publishing — best-effort.
        }
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "New chat messages."
            // Allow this channel to spawn bubbles. The user can still
            // override per-app and per-channel in Settings.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                setAllowBubbles(true)
            }
        }
        nm.createNotificationChannel(channel)
    }

    /**
     * Cancel the chat-bubble notification for a given conversation —
     * called when the user opens the thread inside the app so the
     * banner disappears instead of lingering.
     */
    fun cancel(context: Context, conversationId: Int) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(conversationId)
    }
}
