class ChatUser {
  final String uid;
  final String email;
  final bool isAdmin;
  final String? lastMessage;
  final int? lastMessageTime;
  final bool hasUnreadMessages;

  ChatUser({
    required this.uid,
    required this.email,
    required this.isAdmin,
    this.lastMessage,
    this.lastMessageTime,
    this.hasUnreadMessages = false,
  });

  // Convert from Firebase data to ChatUser
  factory ChatUser.fromMap(Map<String, dynamic> map, String uid) {
    return ChatUser(
      uid: uid,
      email: map['email'] ?? '',
      isAdmin: map['isAdmin'] ?? false,
      lastMessage: map['lastMessage'],
      lastMessageTime: map['lastMessageTime'],
      hasUnreadMessages: map['hasUnreadMessages'] ?? false,
    );
  }

  // Convert to Firebase data
  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'isAdmin': isAdmin,
      'lastMessage': lastMessage,
      'lastMessageTime': lastMessageTime,
      'hasUnreadMessages': hasUnreadMessages,
    };
  }
}
