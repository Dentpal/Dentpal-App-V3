class ChatMessage {
  final String id;
  final String content;
  final String senderId;
  final DateTime timestamp;
  final bool isAdmin;

  ChatMessage({
    required this.id,
    required this.content,
    required this.senderId,
    required this.timestamp,
    required this.isAdmin,
  });

  // Convert from Firebase data to ChatMessage
  factory ChatMessage.fromMap(Map<String, dynamic> map, String id) {
    return ChatMessage(
      id: id,
      content: map['content'] ?? '',
      senderId: map['senderId'] ?? '',
      timestamp: map['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['timestamp'])
          : DateTime.now(),
      isAdmin: map['isAdmin'] ?? false,
    );
  }

  // Convert to Firebase data
  Map<String, dynamic> toMap() {
    return {
      'content': content,
      'senderId': senderId,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'isAdmin': isAdmin,
    };
  }
}
