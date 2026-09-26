package com.tinkerpro.chatbubble;

import android.app.Activity;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.database.Cursor;
import android.media.AudioAttributes;
import android.media.MediaPlayer;
import android.media.RingtoneManager;
import android.graphics.PixelFormat;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import android.util.DisplayMetrics;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.core.app.NotificationCompat;
import androidx.core.app.Person;
import androidx.core.content.FileProvider;
import androidx.core.content.LocusIdCompat;
import androidx.core.content.pm.ShortcutInfoCompat;
import androidx.core.content.pm.ShortcutManagerCompat;
import androidx.core.graphics.drawable.IconCompat;

import java.io.File;
import java.io.FileOutputStream;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.HashMap;
import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public class ChatBubblePlugin implements FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {

    public static final String CHANNEL_NAME = "com.tinkerpro.support/chat_bubble";
    public static final String CHANNEL_ID = "tinkerpro_chat_default";
    private static final String SOUND_CHANNEL_PREFIX = "tp_chat_";
    private static final String SOUND_DIR = "chat_notification_sounds";
    private static final String CHANNEL_LABEL = "TinkerPro Chat";
    private static final String OVERLAY_CHANNEL_ID = "Overlay Channel";
    private static final String OVERLAY_CHANNEL_LABEL = "Chat heads";
    private static final String SHORTCUT_CATEGORY = "com.tinkerpro.support.category.CHAT";
    public static final String EXTRA_CONVERSATION_ID = "chat_conversation_id";

    private static final int CLOSE_TARGET_DP = 64;
    private static final int CLOSE_TARGET_BOTTOM_DP = 72;
    private static MediaPlayer previewPlayer;
    private static FrameLayout closeTarget;
    private static GradientDrawable closeTargetBg;

    private MethodChannel channel;
    private Context context;
    private Activity activity;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        ensureOverlayChannel(context);
        channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        if (channel != null) {
            channel.setMethodCallHandler(null);
            channel = null;
        }
    }

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        activity = binding.getActivity();
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        activity = null;
    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
        activity = binding.getActivity();
    }

    @Override
    public void onDetachedFromActivity() {
        activity = null;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        try {
            switch (call.method) {
                case "show": {
                    int convId = intArg(call, "conversationId");
                    int senderId = intArg(call, "senderId");
                    String sender = stringArg(call, "senderName", "Someone");
                    String body = stringArg(call, "body", "");
                    String channelId = stringArg(call, "channelId", "");
                    if (convId > 0) {
                        show(context, convId, sender, senderId, body, channelId);
                    }
                    result.success(true);
                    break;
                }
                case "cancel": {
                    int convId = intArg(call, "conversationId");
                    if (convId > 0) {
                        notificationManager(context).cancel(convId);
                    }
                    result.success(true);
                    break;
                }
                case "openConversation":
                    result.success(openConversation(intArg(call, "conversationId")));
                    break;
                case "configureSoundChannels": {
                    Object raw = call.argument("channels");
                    result.success(configureSoundChannels(raw instanceof List ? (List<?>) raw : Collections.emptyList()));
                    break;
                }
                case "listDeviceSounds":
                    result.success(listDeviceSounds(stringArg(call, "kind", "notification")));
                    break;
                case "playPreview":
                    result.success(playPreview(
                            stringArg(call, "uri", ""),
                            Boolean.TRUE.equals(call.argument("loop"))));
                    break;
                case "stopPreview":
                    stopPreview();
                    result.success(true);
                    break;
                case "importSound": {
                    Object bytes = call.argument("bytes");
                    result.success(importSound(
                            stringArg(call, "slot", "custom"),
                            stringArg(call, "signature", ""),
                            bytes instanceof byte[] ? (byte[]) bytes : null));
                    break;
                }
                case "screenMetrics":
                    result.success(screenMetrics());
                    break;
                case "bubbleStatus":
                    result.success(status());
                    break;
                case "showCloseTarget":
                    result.success(showCloseTarget());
                    break;
                case "setCloseTargetActive":
                    setCloseTargetActive(Boolean.TRUE.equals(call.argument("active")));
                    result.success(true);
                    break;
                case "hideCloseTarget":
                    hideCloseTarget();
                    result.success(true);
                    break;
                case "openNotificationSettings":
                    result.success(openNotificationSettings());
                    break;
                default:
                    result.notImplemented();
            }
        } catch (Throwable e) {
            result.error("CHAT_BUBBLE_ERROR", e.getMessage(), null);
        }
    }

    private static int intArg(MethodCall call, String key) {
        Object value = call.argument(key);
        return value instanceof Number ? ((Number) value).intValue() : 0;
    }

    private static String stringArg(MethodCall call, String key, String fallback) {
        Object value = call.argument(key);
        return value instanceof String ? (String) value : fallback;
    }

    private static NotificationManager notificationManager(Context ctx) {
        return (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);
    }

    private static int resource(Context ctx, String name, String type) {
        return ctx.getResources().getIdentifier(name, type, ctx.getPackageName());
    }

    private static Intent conversationIntent(Context ctx, int conversationId) {
        Intent launch = ctx.getPackageManager().getLaunchIntentForPackage(ctx.getPackageName());
        ComponentName component = launch != null ? launch.getComponent() : null;
        Intent intent = new Intent(Intent.ACTION_VIEW);
        if (component != null) {
            intent.setComponent(component);
        } else {
            intent.setPackage(ctx.getPackageName());
        }
        intent.setData(Uri.parse("tinkerpro-chat://conversation/" + conversationId));
        intent.putExtra(EXTRA_CONVERSATION_ID, conversationId);
        return intent;
    }

    static void ensureChannel(Context ctx) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return;
        }
        NotificationManager nm = notificationManager(ctx);
        for (String legacy : new String[]{"tinkerpro_chat", "tinkerpro_chat_messages"}) {
            if (nm.getNotificationChannel(legacy) != null) {
                nm.deleteNotificationChannel(legacy);
            }
        }
        if (nm.getNotificationChannel(CHANNEL_ID) != null) {
            return;
        }
        NotificationChannel channel = new NotificationChannel(CHANNEL_ID, CHANNEL_LABEL, NotificationManager.IMPORTANCE_HIGH);
        channel.setDescription("New chat messages.");
        channel.enableVibration(true);
        nm.createNotificationChannel(channel);
    }

    static void ensureOverlayChannel(Context ctx) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return;
        }
        NotificationManager nm = notificationManager(ctx);
        if (nm.getNotificationChannel(OVERLAY_CHANNEL_ID) != null) {
            return;
        }
        NotificationChannel channel = new NotificationChannel(OVERLAY_CHANNEL_ID, OVERLAY_CHANNEL_LABEL, NotificationManager.IMPORTANCE_MIN);
        channel.setDescription("Shown while a chat head is on screen.");
        channel.setSound(null, null);
        channel.setShowBadge(false);
        nm.createNotificationChannel(channel);
    }

    private static String sanitize(String value) {
        String clean = value == null ? "" : value.toLowerCase().replaceAll("[^a-z0-9]", "");
        return clean.length() > 24 ? clean.substring(0, 24) : clean;
    }

    private static Uri soundUri(Context ctx, File file) {
        return FileProvider.getUriForFile(ctx, ctx.getPackageName() + ".chatbubble.sounds", file);
    }

    private static void grantSound(Context ctx, Uri uri) {
        if (uri == null || !"content".equals(uri.getScheme())) {
            return;
        }
        for (String pkg : new String[]{"com.android.systemui", "android"}) {
            try {
                ctx.grantUriPermission(pkg, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION);
            } catch (Throwable ignored) {
            }
        }
    }

    private List<Map<String, Object>> listDeviceSounds(String kind) {
        List<Map<String, Object>> out = new ArrayList<>();
        int type = "ringtone".equals(kind)
                ? RingtoneManager.TYPE_RINGTONE
                : RingtoneManager.TYPE_NOTIFICATION;
        try {
            RingtoneManager manager = new RingtoneManager(context);
            manager.setType(type);
            Cursor cursor = manager.getCursor();
            while (cursor != null && cursor.moveToNext()) {
                Map<String, Object> row = new HashMap<>();
                row.put("title", cursor.getString(RingtoneManager.TITLE_COLUMN_INDEX));
                row.put("uri", manager.getRingtoneUri(cursor.getPosition()).toString());
                out.add(row);
                if (out.size() >= 120) {
                    break;
                }
            }
        } catch (Throwable ignored) {
        }
        return out;
    }

    private boolean playPreview(String uri, boolean loop) {
        stopPreview();
        if (uri == null || uri.isEmpty()) {
            return false;
        }
        try {
            MediaPlayer player = new MediaPlayer();
            player.setAudioAttributes(new AudioAttributes.Builder()
                    .setUsage(loop ? AudioAttributes.USAGE_NOTIFICATION_RINGTONE : AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build());
            player.setDataSource(context, Uri.parse(uri));
            player.setLooping(loop);
            player.setOnCompletionListener(mp -> {
                if (!loop) {
                    stopPreview();
                }
            });
            player.prepare();
            player.start();
            previewPlayer = player;
            return true;
        } catch (Throwable e) {
            stopPreview();
            return false;
        }
    }

    private void stopPreview() {
        MediaPlayer player = previewPlayer;
        previewPlayer = null;
        if (player == null) {
            return;
        }
        try {
            player.stop();
        } catch (Throwable ignored) {
        }
        try {
            player.release();
        } catch (Throwable ignored) {
        }
    }

    private String importSound(String slot, String signature, byte[] bytes) {
        if (bytes == null || bytes.length == 0) {
            return "";
        }
        try {
            File dir = new File(context.getFilesDir(), SOUND_DIR);
            if (!dir.exists()) {
                dir.mkdirs();
            }
            String name = sanitize(slot) + "_" + sanitize(signature) + ".snd";
            File file = new File(dir, name);
            try (FileOutputStream stream = new FileOutputStream(file)) {
                stream.write(bytes);
            }
            File[] files = dir.listFiles();
            if (files != null) {
                for (File f : files) {
                    if (f.getName().startsWith(sanitize(slot) + "_") && !f.getName().equals(name)) {
                        f.delete();
                    }
                }
            }
            Uri uri = soundUri(context, file);
            grantSound(context, uri);
            return uri.toString();
        } catch (Throwable e) {
            return "";
        }
    }

    private Map<String, Object> configureSoundChannels(List<?> specs) {
        Map<String, Object> out = new HashMap<>();
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return out;
        }
        NotificationManager nm = notificationManager(context);
        ensureChannel(context);
        File dir = new File(context.getFilesDir(), SOUND_DIR);
        if (!dir.exists()) {
            dir.mkdirs();
        }
        for (Object item : specs) {
            if (!(item instanceof Map)) {
                continue;
            }
            Map<?, ?> spec = (Map<?, ?>) item;
            String event = sanitize(String.valueOf(spec.get("event")));
            String signature = sanitize(String.valueOf(spec.get("signature")));
            Object label = spec.get("label");
            Object bytes = spec.get("bytes");
            Object soundUri = spec.get("uri");
            boolean silent = Boolean.TRUE.equals(spec.get("silent"));
            if (event.isEmpty() || signature.isEmpty()) {
                continue;
            }
            String prefix = SOUND_CHANNEL_PREFIX + event + "_";
            String channelId = prefix + signature;
            try {
                Uri uri = null;
                if (!silent && soundUri instanceof String && !((String) soundUri).isEmpty()) {
                    uri = Uri.parse((String) soundUri);
                    grantSound(context, uri);
                } else if (!silent && bytes instanceof byte[] && ((byte[]) bytes).length > 0) {
                    File file = new File(dir, event + "_" + signature + ".snd");
                    if (!file.exists() || file.length() != ((byte[]) bytes).length) {
                        try (FileOutputStream stream = new FileOutputStream(file)) {
                            stream.write((byte[]) bytes);
                        }
                    }
                    uri = soundUri(context, file);
                    grantSound(context, uri);
                }
                if (nm.getNotificationChannel(channelId) == null) {
                    NotificationChannel channel = new NotificationChannel(
                            channelId,
                            label instanceof String ? (String) label : CHANNEL_LABEL,
                            NotificationManager.IMPORTANCE_HIGH);
                    channel.setDescription("Uses the sound picked in TinkerPro web settings.");
                    channel.enableVibration(true);
                    if (silent) {
                        channel.setSound(null, null);
                    } else {
                        AudioAttributes attrs = new AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                .build();
                        channel.setSound(uri != null ? uri : RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION), attrs);
                    }
                    nm.createNotificationChannel(channel);
                }
                for (NotificationChannel existing : nm.getNotificationChannels()) {
                    String id = existing.getId();
                    if (id.startsWith(prefix) && !id.equals(channelId)) {
                        nm.deleteNotificationChannel(id);
                    }
                }
                File[] files = dir.listFiles();
                if (files != null) {
                    for (File f : files) {
                        if (f.getName().startsWith(event + "_") && !f.getName().equals(event + "_" + signature + ".snd")) {
                            f.delete();
                        }
                    }
                }
                out.put(event, channelId);
            } catch (Throwable e) {
                out.put(event, CHANNEL_ID);
            }
        }
        return out;
    }

    static void show(Context ctx, int conversationId, String senderName, int senderId, String body, String channelId) {
        ensureChannel(ctx);
        NotificationManager manager = notificationManager(ctx);
        String targetChannel = CHANNEL_ID;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && channelId != null && !channelId.isEmpty()) {
            NotificationChannel picked = manager.getNotificationChannel(channelId);
            if (picked != null) {
                targetChannel = channelId;
                grantSound(ctx, picked.getSound());
            }
        }
        String shortcutId = "chat-conv-" + conversationId;

        Person sender = new Person.Builder()
                .setKey(String.valueOf(senderId))
                .setName(senderName)
                .setImportant(true)
                .build();

        publishShortcut(ctx, shortcutId, conversationId, sender);

        int flags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags |= PendingIntent.FLAG_IMMUTABLE;
        }
        PendingIntent contentIntent = PendingIntent.getActivity(
                ctx,
                conversationId,
                conversationIntent(ctx, conversationId)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP),
                flags);

        NotificationCompat.MessagingStyle style = new NotificationCompat.MessagingStyle(
                new Person.Builder().setName("You").build());
        style.addMessage(new NotificationCompat.MessagingStyle.Message(body, System.currentTimeMillis(), sender));

        NotificationCompat.Builder builder = new NotificationCompat.Builder(ctx, targetChannel)
                .setSmallIcon(resource(ctx, "ic_launcher", "mipmap"))
                .setStyle(style)
                .setShortcutId(shortcutId)
                .setLocusId(new LocusIdCompat(shortcutId))
                .addPerson(sender)
                .setContentIntent(contentIntent)
                .setCategory(NotificationCompat.CATEGORY_MESSAGE)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setShowWhen(true)
                .setAutoCancel(true);

        notificationManager(ctx).notify(conversationId, builder.build());
    }

    private static void publishShortcut(Context ctx, String shortcutId, int conversationId, Person person) {
        int iconId = resource(ctx, "ic_launcher", "mipmap");
        ShortcutInfoCompat shortcut = new ShortcutInfoCompat.Builder(ctx, shortcutId)
                .setLongLived(true)
                .setShortLabel(String.valueOf(person.getName()))
                .setLongLabel(String.valueOf(person.getName()))
                .setIcon(IconCompat.createWithResource(ctx, iconId))
                .setIntent(conversationIntent(ctx, conversationId))
                .setLocusId(new LocusIdCompat(shortcutId))
                .setCategories(Collections.singleton(SHORTCUT_CATEGORY))
                .setPerson(person)
                .build();
        try {
            ShortcutManagerCompat.pushDynamicShortcut(ctx, shortcut);
        } catch (Throwable ignored) {
        }
    }

    private boolean openConversation(int conversationId) {
        Intent intent = conversationId > 0
                ? conversationIntent(context, conversationId)
                : context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
        if (intent == null) {
            return false;
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        try {
            context.startActivity(intent);
            return true;
        } catch (Throwable e) {
            return false;
        }
    }

    private int dp(int value) {
        return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value, context.getResources().getDisplayMetrics());
    }

    private boolean showCloseTarget() {
        if (closeTarget != null) {
            return true;
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(context)) {
            return false;
        }
        try {
            WindowManager wm = (WindowManager) context.getSystemService(Context.WINDOW_SERVICE);
            closeTargetBg = new GradientDrawable();
            closeTargetBg.setShape(GradientDrawable.OVAL);
            closeTargetBg.setColor(Color.argb(200, 20, 20, 20));
            closeTargetBg.setStroke(dp(2), Color.WHITE);

            TextView label = new TextView(context);
            label.setText("\u2715");
            label.setTextColor(Color.WHITE);
            label.setTextSize(TypedValue.COMPLEX_UNIT_SP, 26);
            label.setGravity(Gravity.CENTER);

            FrameLayout frame = new FrameLayout(context);
            frame.setBackground(closeTargetBg);
            frame.addView(label, new FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));

            int type = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                    ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                    : WindowManager.LayoutParams.TYPE_PHONE;
            WindowManager.LayoutParams params = new WindowManager.LayoutParams(
                    dp(CLOSE_TARGET_DP),
                    dp(CLOSE_TARGET_DP),
                    type,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
                    PixelFormat.TRANSLUCENT);
            params.gravity = Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL;
            params.y = dp(CLOSE_TARGET_BOTTOM_DP);
            wm.addView(frame, params);
            closeTarget = frame;
            return true;
        } catch (Throwable e) {
            closeTarget = null;
            return false;
        }
    }

    private void setCloseTargetActive(boolean active) {
        if (closeTarget == null || closeTargetBg == null) {
            return;
        }
        closeTargetBg.setColor(active ? Color.rgb(229, 57, 53) : Color.argb(200, 20, 20, 20));
        float scale = active ? 1.25f : 1f;
        closeTarget.setScaleX(scale);
        closeTarget.setScaleY(scale);
    }

    private void hideCloseTarget() {
        View view = closeTarget;
        closeTarget = null;
        closeTargetBg = null;
        if (view == null) {
            return;
        }
        try {
            WindowManager wm = (WindowManager) context.getSystemService(Context.WINDOW_SERVICE);
            wm.removeView(view);
        } catch (Throwable ignored) {
        }
    }

    private Map<String, Object> screenMetrics() {
        DisplayMetrics metrics = new DisplayMetrics();
        WindowManager wm = (WindowManager) context.getSystemService(Context.WINDOW_SERVICE);
        wm.getDefaultDisplay().getRealMetrics(metrics);
        Map<String, Object> out = new HashMap<>();
        out.put("density", (double) metrics.density);
        out.put("width", metrics.widthPixels);
        out.put("height", metrics.heightPixels);
        return out;
    }

    private Map<String, Object> status() {
        NotificationManager nm = notificationManager(context);
        boolean supported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.M;
        Map<String, Object> out = new HashMap<>();
        out.put("sdk", Build.VERSION.SDK_INT);
        out.put("supported", supported);
        out.put("notifications", nm.areNotificationsEnabled());
        out.put("overlay", supported && Settings.canDrawOverlays(context));
        return out;
    }

    private boolean openNotificationSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent intent = new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, context.getPackageName());
            if (tryStart(intent)) {
                return true;
            }
        }
        return tryStart(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.fromParts("package", context.getPackageName(), null)));
    }

    private boolean tryStart(Intent intent) {
        try {
            if (activity != null) {
                activity.startActivity(intent);
            } else {
                context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            }
            return true;
        } catch (Throwable e) {
            return false;
        }
    }
}
