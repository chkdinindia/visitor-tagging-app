String _two(int n) => n.toString().padLeft(2, '0');

/// "just now", "45s ago", "3m ago", "2h ago", "never".
String timeAgo(DateTime? time) {
  if (time == null) return 'never';
  final diff = DateTime.now().toUtc().difference(time.toUtc());
  if (diff.inSeconds < 10) return 'just now';
  if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

/// Local "HH:mm".
String clockTime(DateTime time) {
  final t = time.toLocal();
  return '${_two(t.hour)}:${_two(t.minute)}';
}

/// Local "yyyy-MM-dd HH:mm:ss".
String fullLocalTime(DateTime? time) {
  if (time == null) return '—';
  final t = time.toLocal();
  return '${t.year}-${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';
}

/// UTC "yyyy-MM-dd HH:mm:ss UTC".
String fullUtcTime(DateTime? time) {
  if (time == null) return '—';
  final t = time.toUtc();
  return '${t.year}-${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)} UTC';
}
