/// Compact relative timestamps for lists (e.g. "just now", "5m ago",
/// "yesterday", "11 Aug").
String relativeTime(DateTime time, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final difference = reference.difference(time);

  if (difference.inSeconds < 60) return 'just now';
  if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
  if (difference.inHours < 24 && reference.day == time.day) {
    return '${difference.inHours}h ago';
  }
  if (difference.inDays < 2) return 'yesterday';
  if (reference.year == time.year) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${time.day} ${months[time.month - 1]}';
  }
  return '${time.day} ${_shortMonth(time.month)} ${time.year}';
}

String _shortMonth(int month) => const [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ][month - 1];
