import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/chat_message.dart';
import '../models/chat_user.dart';

class ChatService {
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Create a new chat
  Future<String> createChat(String userId) async {
    final chatRef = _database.ref('chats').push();
    final String chatId = chatRef.key!;
    
    await chatRef.set({
      'users': {
        userId: true,
      },
      'createdAt': ServerValue.timestamp,
      'updatedAt': ServerValue.timestamp,
    });
    
    return chatId;
  }

  // Find existing chat for user - avoid using deep path queries
  Future<String?> findChatForUser(String userId) async {
    // Get all chats
    final snapshot = await _database.ref('chats').get();
    
    if (!snapshot.exists) {
      return null;
    }
    
    // Filter on client side
    for (var chatSnapshot in snapshot.children) {
      final chatData = chatSnapshot.value as Map<dynamic, dynamic>?;
      if (chatData != null && chatData['users'] != null) {
        final users = chatData['users'] as Map<dynamic, dynamic>;
        if (users.containsKey(userId) && users[userId] == true) {
          return chatSnapshot.key;
        }
      }
    }
    
    return null;
  }

  // Get or create chat for user
  Future<String> getOrCreateChatForUser(String userId) async {
    String? existingChatId = await findChatForUser(userId);
    if (existingChatId != null) {
      return existingChatId;
    }
    
    return await createChat(userId);
  }

  // Send message
  Future<void> sendMessage({
    required String chatId,
    required String content,
    required bool isAdmin,
  }) async {
    final User? currentUser = _auth.currentUser;
    if (currentUser == null) return;
    
    final messageRef = _database.ref('chats/$chatId/messages').push();
    
    await messageRef.set({
      'content': content,
      'senderId': currentUser.uid,
      'timestamp': ServerValue.timestamp,
      'isAdmin': isAdmin,
    });
    
    // Update chat's last message
    await _database.ref('chats/$chatId').update({
      'lastMessage': content,
      'lastMessageTime': ServerValue.timestamp,
      'updatedAt': ServerValue.timestamp,
    });
    
    // Set unread message flag for other users
    final snapshot = await _database.ref('chats/$chatId/users').get();
    if (snapshot.exists) {
      Map<dynamic, dynamic> users = snapshot.value as Map<dynamic, dynamic>;
      for (var userId in users.keys) {
        if (userId != currentUser.uid) {
          await _database.ref('chats/$chatId/users/$userId').set(true);
          await _database.ref('users/$userId/chats/$chatId/hasUnreadMessages').set(true);
        }
      }
    }
  }

  // Get all users for admin - filtering non-admin users
  Stream<List<ChatUser>> getUsersForAdmin() {
    return _database.ref('users')
      .onValue
      .map((event) {
        List<ChatUser> users = [];
        if (event.snapshot.value != null) {
          Map<dynamic, dynamic> usersData = 
              event.snapshot.value as Map<dynamic, dynamic>;
          usersData.forEach((key, value) {
            // Filter non-admin users on client side
            Map<String, dynamic> userData = Map<String, dynamic>.from(value as Map);
            if (userData['isAdmin'] != true) {
              users.add(ChatUser.fromMap(userData, key as String));
            }
          });
        }
        return users;
      });
  }

  // Stream chat messages
  Stream<List<ChatMessage>> getChatMessages(String chatId) {
    return _database.ref('chats/$chatId/messages')
      .orderByChild('timestamp')
      .onValue
      .map((event) {
        List<ChatMessage> messages = [];
        if (event.snapshot.value != null) {
          Map<dynamic, dynamic> messagesData = 
              event.snapshot.value as Map<dynamic, dynamic>;
          messagesData.forEach((key, value) {
            messages.add(ChatMessage.fromMap(
              Map<String, dynamic>.from(value as Map), 
              key as String
            ));
          });
          // Sort by timestamp
          messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        }
        return messages;
      });
  }

  // Add admin to chat
  Future<void> addAdminToChat(String chatId, String adminId) async {
    await _database.ref('chats/$chatId/users/$adminId').set(true);
    
    // Send system notification message
    final messageRef = _database.ref('chats/$chatId/messages').push();
    await messageRef.set({
      'content': 'You are now chatting with an admin.',
      'senderId': 'system',
      'timestamp': ServerValue.timestamp,
      'isAdmin': true,
    });
  }

  // Mark messages as read
  Future<void> markMessagesAsRead(String chatId, String userId) async {
    await _database.ref('users/$userId/chats/$chatId/hasUnreadMessages').set(false);
  }
}
