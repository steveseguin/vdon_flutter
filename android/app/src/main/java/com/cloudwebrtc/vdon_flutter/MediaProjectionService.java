package com.cloudwebrtc.vdon_flutter;

import android.app.*;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;
import android.util.Log;
import androidx.core.app.NotificationCompat;
import androidx.core.content.ContextCompat;

public class MediaProjectionService extends Service {

    private static final String TAG = "VDONinja";
    private static final String CHANNEL_ID = "media_projection_channel";
    private static final int NOTIFICATION_ID = 999;
    private static final String ACTION_START = "com.cloudwebrtc.vdon_flutter.START_MEDIA_PROJECTION";

    private static volatile boolean isRunning = false;

    public static boolean startService(Context context) {
        Intent intent = new Intent(context, MediaProjectionService.class);
        intent.setAction(ACTION_START);
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(context, intent);
            } else {
                context.startService(intent);
            }
            Log.d(TAG, "Requested MediaProjectionService start");
            return true;
        } catch (Exception e) {
            Log.e(TAG, "Unable to start MediaProjectionService", e);
            return false;
        }
    }

    public static boolean stopService(Context context) {
        try {
            boolean stopped = context.stopService(new Intent(context, MediaProjectionService.class));
            if (stopped) {
                Log.d(TAG, "MediaProjectionService stop requested");
            } else {
                Log.w(TAG, "MediaProjectionService stop request returned false");
            }
            return stopped;
        } catch (Exception e) {
            Log.e(TAG, "Unable to stop MediaProjectionService", e);
            return false;
        }
    }

    public static boolean isRunning() {
        return isRunning;
    }

    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannel();
        Log.d(TAG, "MediaProjectionService created");
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        Log.d(TAG, "MediaProjectionService onStartCommand action=" + (intent != null ? intent.getAction() : "null"));
        if (intent == null || ACTION_START.equals(intent.getAction())) {
            enterForeground();
        } else {
            Log.w(TAG, "MediaProjectionService received unsupported action: " + intent.getAction());
        }
        return START_NOT_STICKY;
    }

    private void enterForeground() {
        Notification notification = createNotification();

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            );
        } else {
            startForeground(NOTIFICATION_ID, notification);
        }
        isRunning = true;
        Log.d(TAG, "MediaProjectionService entered foreground");
    }

    @Override
    public void onDestroy() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE);
            } else {
                stopForeground(true);
            }
        } catch (Exception e) {
            Log.w(TAG, "Failed to stop MediaProjectionService foreground state", e);
        }
        isRunning = false;
        Log.d(TAG, "MediaProjectionService destroyed");
        super.onDestroy();
    }

    private Notification createNotification() {
        Intent notificationIntent = getPackageManager().getLaunchIntentForPackage(getPackageName());
        PendingIntent pendingIntent = PendingIntent.getActivity(
            this,
            0,
            notificationIntent,
            PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT
        );

        return new NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Screen Sharing Active")
            .setContentText("VDO.Ninja is sharing your screen")
            .setSmallIcon(android.R.drawable.ic_menu_share)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build();
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID,
                "Screen Sharing",
                NotificationManager.IMPORTANCE_LOW
            );
            channel.setDescription("Notification for screen sharing service");
            channel.setShowBadge(false);
            channel.enableVibration(false);

            NotificationManager notificationManager = getSystemService(NotificationManager.class);
            notificationManager.createNotificationChannel(channel);
        }
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
