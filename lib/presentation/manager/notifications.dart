import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:vikunja_app/core/network/client.dart';
import 'package:vikunja_app/data/data_sources/settings_data_source.dart';
import 'package:vikunja_app/data/data_sources/task_data_source.dart';
import 'package:vikunja_app/data/repositories/task_repository_impl.dart';
import 'package:vikunja_app/domain/entities/task.dart';
import 'package:vikunja_app/domain/repositories/task_repository.dart';
import 'package:vikunja_app/presentation/manager/pagination_mixin.dart';
import 'package:vikunja_app/presentation/manager/widget_controller.dart';

const _actionDonePortName = 'action_done_port_name';
const _notificationActionDone = 'action_done';

@pragma('vm:entry-point')
Future<void> notificationTapBackground(
  NotificationResponse notificationResponse,
) async {
  if (notificationResponse.actionId == _notificationActionDone) {
    var payload = notificationResponse.payload;

    if (payload != null) {
      var id = int.tryParse(payload);
      if (id != null) {
        await markAsDone(id);
      }
    }
  }
}

Future<void> markAsDone(int id) async {
  var datasource = SettingsDatasource(FlutterSecureStorage());
  var refreshToken = await datasource.getRefreshToken();
  var base = await datasource.getServer();

  if (refreshToken == null || base == null) {
    return;
  }

  Client client = Client(base: base);

  var ignoreCertificates = await datasource.getIgnoreCertificates();
  client.setIgnoreCerts(ignoreCertificates);

  TaskRepository taskService = TaskRepositoryImpl(TaskDataSource(client));
  var response = await taskService.getTask(id);

  if (response.isSuccessful) {
    var task = response.toSuccess().body;
    task.done = true;
    await taskService.update(task);

    await updateWidget();

    //Call app if opened to update view
    final SendPort? sendPort = IsolateNameServer.lookupPortByName(
      _actionDonePortName,
    );

    if (sendPort != null) {
      sendPort.send(task.id);
    }
  }
}

class NotificationHandler {
  final ReceivePort _receivePort = ReceivePort();
  final List<Function()> _taskChangedListener = List.empty(growable: true);

  FlutterLocalNotificationsPlugin get notificationsPlugin =>
      FlutterLocalNotificationsPlugin();

  var androidSpecificsDueDate = AndroidNotificationDetails(
    "Vikunja1",
    "Due Date Notifications",
    channelDescription: "description",
    icon: 'vikunja_notification_logo',
    importance: Importance.high,
    actions: <AndroidNotificationAction>[
      AndroidNotificationAction(_notificationActionDone, 'Done'),
    ],
  );
  var androidSpecificsReminders = AndroidNotificationDetails(
    "Vikunja2",
    "Reminder Notifications",
    channelDescription: "description",
    icon: 'vikunja_notification_logo',
    importance: Importance.high,
    actions: <AndroidNotificationAction>[
      AndroidNotificationAction(_notificationActionDone, 'Done'),
    ],
  );
  late DarwinNotificationDetails iOSSpecifics;
  late NotificationDetails platformChannelSpecificsDueDate;
  late NotificationDetails platformChannelSpecificsReminders;

  NotificationHandler();

  Future<void> requestPermissions() async {
    if (Platform.isIOS) {
      await requestIOSPermissions();
    } else if (Platform.isAndroid) {
      await requestAndroidPermissions();
    }
  }

  Future<void> initNotifications() async {
    iOSSpecifics = DarwinNotificationDetails(
      categoryIdentifier: 'doneCategory',
    );
    platformChannelSpecificsDueDate = NotificationDetails(
      android: androidSpecificsDueDate,
      iOS: iOSSpecifics,
    );
    platformChannelSpecificsReminders = NotificationDetails(
      android: androidSpecificsReminders,
      iOS: iOSSpecifics,
    );
    var initializationSettingsAndroid = AndroidInitializationSettings(
      'vikunja_logo',
    );
    var initializationSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: [
        DarwinNotificationCategory(
          'doneCategory',
          actions: <DarwinNotificationAction>[
            DarwinNotificationAction.plain(_notificationActionDone, 'Done'),
          ],
        ),
      ],
    );
    var initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );
    await notificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
    developer.log("Notifications initialised successfully");

    initBackgroundCommunication();
  }

  void initBackgroundCommunication() {
    IsolateNameServer.removePortNameMapping(_actionDonePortName);

    final ok = IsolateNameServer.registerPortWithName(
      _receivePort.sendPort,
      _actionDonePortName,
    );
    if (!ok) {
      developer.log('Failed to register $_actionDonePortName');
    }

    _receivePort.listen((dynamic message) {
      for (var it in _taskChangedListener) {
        it.call();
      }
    });
  }

  Future<void> scheduleNotification(
    int id,
    String title,
    String description,
    FlutterLocalNotificationsPlugin notifsPlugin,
    DateTime scheduledTime,
    NotificationDetails platformChannelSpecifics,
    AndroidScheduleMode mode, {
    String? payload,
  }) async {
    var currentTimeZone = await FlutterTimezone.getLocalTimezone();

    tz.TZDateTime time = tz.TZDateTime.from(
      scheduledTime,
      tz.getLocation(currentTimeZone),
    );

    if (time.difference(tz.TZDateTime.now(tz.getLocation(currentTimeZone))) <
        Duration.zero) {
      return;
    }

    developer.log("scheduled notification for time $time with id $id and payload $payload");

    await notifsPlugin.zonedSchedule(
      id: id,
      title: title,
      body: description,
      scheduledDate: time,
      notificationDetails: platformChannelSpecifics,
      androidScheduleMode: mode,
      payload: payload ?? id.toString(),
    );
  }

  void sendTestNotification() {
    notificationsPlugin.show(
      id: Random().nextInt(10000000),
      title: "Test Notification",
      body: "This is a test notification",
      notificationDetails: platformChannelSpecificsReminders,
    );
  }

  Future<void> requestIOSPermissions() async {
    await notificationsPlugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<void> requestAndroidPermissions() async {
    final androidPlugin = notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidPlugin == null) return;

    await androidPlugin.requestNotificationsPermission();

    final canSchedule = await androidPlugin.canScheduleExactNotifications();
    if (canSchedule != true) {
      await androidPlugin.requestExactAlarmsPermission();
    }
  }

  Future<void> scheduleNotifications(TaskRepository taskService) async {
    List<Task> allTasks = [];
    int currentPage = 1;
    bool hasMore = true;

    while (hasMore) {
      var taskResponse = await taskService.getByFilterString(
        "done=false && (due_date > now || reminders > now)",
        {
          "filter_include_nulls": ["false"],
          "page": [currentPage.toString()],
        },
      );

      if (taskResponse.isSuccessful) {
        var tasks = taskResponse.toSuccess().body;
        if (tasks.isEmpty) {
          hasMore = false;
        } else {
          allTasks.addAll(tasks);
          currentPage++;

          var headers = taskResponse.toSuccess().headers;
          var totalPagesStr = headers[PaginationMixin.paginationHeader] ??
              headers[PaginationMixin.paginationHeader];
          if (totalPagesStr != null) {
            int? totalPages = int.tryParse(totalPagesStr);
            if (totalPages != null && currentPage > totalPages) {
              hasMore = false;
            }
          }
        }
      } else {
        hasMore = false;
      }

      // Safety break to prevent infinite loops and hitting system limits
      // Android generally limits to 500 scheduled alarms.
      if (allTasks.length > 450) {
        allTasks = allTasks.sublist(0, 450);
        hasMore = false;
      }
    }

    final androidPlugin = notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    AndroidScheduleMode mode = AndroidScheduleMode.inexactAllowWhileIdle;
    if (androidPlugin != null) {
      final canSchedule = await androidPlugin.canScheduleExactNotifications();
      if (canSchedule == true) {
        mode = AndroidScheduleMode.exactAllowWhileIdle;
      }
    }

    if (allTasks.isNotEmpty) {
      await notificationsPlugin.cancelAll();
      for (final task in allTasks) {
        if (task.done) continue;
        for (var i = 0; i < task.reminderDates.length; i++) {
          final reminder = task.reminderDates[i];
          int notificationId = task.getReminderNotificationId(reminder.dateTime);
          await scheduleNotification(
            notificationId,
            "Reminder",
            "This is your reminder for '${task.title}'",
            notificationsPlugin,
            reminder.dateTime,
            platformChannelSpecificsReminders,
            mode,
            payload: task.id.toString(),
          );
        }
        if (task.hasDueDate) {
          await scheduleNotification(
            task.id,
            "Due Reminder",
            "The task '${task.title}' is due.",
            notificationsPlugin,
            task.dueDate!,
            platformChannelSpecificsDueDate,
            mode,
            payload: task.id.toString(),
          );
        }
      }
      developer.log("notifications scheduled successfully");
    }
  }

  void addListener(Function() listener) {
    _taskChangedListener.add(listener);
  }

  void removeListener(Function() listener) {
    _taskChangedListener.remove(listener);
  }
}
