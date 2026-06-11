class Activity {
  const Activity({
    required this.id,
    required this.message,
    required this.actor,
    required this.createdAt,
  });

  final String id;
  final String message;
  final String actor;
  final DateTime createdAt;
}
