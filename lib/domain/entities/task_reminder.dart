class TaskReminder {
  final int relativePeriod;
  final String relativeTo;
  DateTime dateTime;

  TaskReminder(this.dateTime, [this.relativePeriod = 0, this.relativeTo = ""]);

  TaskReminder.fromJson(Map<String, dynamic> json)
    : dateTime = DateTime.parse(json['reminder']),
      relativePeriod = json['relative_period'],
      relativeTo = json['relative_to'];

  Map<String, Object> toJSON() => {
    'relative_period': relativePeriod,
    'relative_to': relativeTo,
    'reminder': dateTime.toUtc().toIso8601String(),
  };
}
