import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dentpal/utils/app_logger.dart';

class ChatMessage {
  final String id;
  final String senderId;
  final String receiverId;
  final String message;
  final DateTime timestamp;
  final String? senderName;
  final String? senderAvatar;
  final bool isRead;
  final String? productId;
  final String? productName;
  final String? productImage;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.message,
    required this.timestamp,
    this.senderName,
    this.senderAvatar,
    this.isRead = false,
    this.productId,
    this.productName,
    this.productImage,
  });

  factory ChatMessage.fromMap(String id, Map<dynamic, dynamic> data) {
    return ChatMessage(
      id: id,
      senderId: data['senderId'] ?? '',
      receiverId: data['receiverId'] ?? '',
      message: data['message'] ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(data['timestamp'] ?? 0),
      senderName: data['senderName'],
      senderAvatar: data['senderAvatar'],
      isRead: data['isRead'] ?? false,
      productId: data['productId'],
      productName: data['productName'],
      productImage: data['productImage'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'receiverId': receiverId,
      'message': message,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'senderName': senderName,
      'senderAvatar': senderAvatar,
      'isRead': isRead,
      'productId': productId,
      'productName': productName,
      'productImage': productImage,
    };
  }
}

class ChatRoom {
  final String id;
  final String user1Id;
  final String user2Id;
  final String user1Name;
  final String user2Name;
  final String? user1Avatar;
  final String? user2Avatar;
  final String? user1ShopName;
  final String? user2ShopName;
  final ChatMessage? lastMessage;
  final DateTime lastActivity;
  final int unreadCount;

  ChatRoom({
    required this.id,
    required this.user1Id,
    required this.user2Id,
    required this.user1Name,
    required this.user2Name,
    this.user1Avatar,
    this.user2Avatar,
    this.user1ShopName,
    this.user2ShopName,
    this.lastMessage,
    required this.lastActivity,
    this.unreadCount = 0,
  });

  factory ChatRoom.fromMap(String id, Map<dynamic, dynamic> data) {
    ChatMessage? lastMessage;
    if (data['lastMessage'] != null) {
      lastMessage = ChatMessage.fromMap('last', data['lastMessage']);
    }

    return ChatRoom(
      id: id,
      user1Id: data['user1Id'] ?? '',
      user2Id: data['user2Id'] ?? '',
      user1Name: data['user1Name'] ?? '',
      user2Name: data['user2Name'] ?? '',
      user1Avatar: data['user1Avatar'],
      user2Avatar: data['user2Avatar'],
      user1ShopName: data['user1ShopName'],
      user2ShopName: data['user2ShopName'],
      lastMessage: lastMessage,
      lastActivity: DateTime.fromMillisecondsSinceEpoch(data['lastActivity'] ?? 0),
      unreadCount: data['unreadCount'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'user1Id': user1Id,
      'user2Id': user2Id,
      'user1Name': user1Name,
      'user2Name': user2Name,
      'user1Avatar': user1Avatar,
      'user2Avatar': user2Avatar,
      'user1ShopName': user1ShopName,
      'user2ShopName': user2ShopName,
      'lastMessage': lastMessage?.toMap(),
      'lastActivity': lastActivity.millisecondsSinceEpoch,
      'unreadCount': unreadCount,
    };
  }

  String getOtherUserName(String currentUserId) {
    return currentUserId == user1Id ? user2Name : user1Name;
  }

  String? getOtherUserAvatar(String currentUserId) {
    return currentUserId == user1Id ? user2Avatar : user1Avatar;
  }

  String? getOtherUserShopName(String currentUserId) {
    return currentUserId == user1Id ? user2ShopName : user1ShopName;
  }

  String getOtherUserId(String currentUserId) {
    return currentUserId == user1Id ? user2Id : user1Id;
  }

  // New method to get the display name based on user roles
  String getDisplayName(String currentUserId) {
    // If current user is user1
    if (currentUserId == user1Id) {
      // Show user2's info
      // If user2 is a seller, show shop name; otherwise show full name
      if (user2ShopName != null && user2ShopName!.isNotEmpty) {
        return user2ShopName!;
      } else {
        return user2Name;
      }
    } else {
      // Show user1's info
      // If user1 is a seller, show shop name; otherwise show full name
      if (user1ShopName != null && user1ShopName!.isNotEmpty) {
        return user1ShopName!;
      } else {
        return user1Name;
      }
    }
  }

  // New method to get subtitle (user type info)
  String? getDisplaySubtitle(String currentUserId) {
    // No subtitle needed - we only show shop name or full name, not both
    return null;
  }
}

class ChatService {
  static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;

  late final FirebaseDatabase _database;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  ChatService._internal() {
    _database = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: 'https://dentpal-161e5-default-rtdb.asia-southeast1.firebasedatabase.app/',
    );
  }

  // Update existing chat room with correct user names
  Future<void> updateChatRoomUserData(String chatRoomId, String user1Id, String user2Id) async {
    try {
      final chatRoomRef = _database.ref('chatRooms/$chatRoomId');
      
      // Get user data from Firestore
      final user1Doc = await _firestore.collection('User').doc(user1Id).get();
      final user2Doc = await _firestore.collection('User').doc(user2Id).get();

      String user1Name = user1Doc.data()?['fullName'] ?? 
                         user1Doc.data()?['displayName'] ?? 'User';
      String user2Name = user2Doc.data()?['fullName'] ?? 
                         user2Doc.data()?['displayName'] ?? 'User';

      // Get user avatars from User collection
      String? user1Avatar = user1Doc.data()?['photoURL'];
      String? user2Avatar = user2Doc.data()?['photoURL'];

      // Check if users are sellers to get shop names and seller avatars
      String? user1ShopName;
      String? user2ShopName;

      if (user1Doc.data()?['role'] == 'seller') {
        final sellerDoc = await _firestore.collection('Seller').doc(user1Id).get();
        user1ShopName = sellerDoc.data()?['shopName'];
        // Use seller's photoURL if available, otherwise keep user's photoURL
        String? sellerPhotoURL = sellerDoc.data()?['photoURL'];
        if (sellerPhotoURL != null && sellerPhotoURL.isNotEmpty) {
          user1Avatar = sellerPhotoURL;
        }
      }

      if (user2Doc.data()?['role'] == 'seller') {
        final sellerDoc = await _firestore.collection('Seller').doc(user2Id).get();
        user2ShopName = sellerDoc.data()?['shopName'];
        // Use seller's photoURL if available, otherwise keep user's photoURL
        String? sellerPhotoURL = sellerDoc.data()?['photoURL'];
        if (sellerPhotoURL != null && sellerPhotoURL.isNotEmpty) {
          user2Avatar = sellerPhotoURL;
        }
      }

      // Update chat room with correct names and avatars
      await chatRoomRef.update({
        'user1Name': user1Name,
        'user2Name': user2Name,
        'user1Avatar': user1Avatar,
        'user2Avatar': user2Avatar,
        'user1ShopName': user1ShopName,
        'user2ShopName': user2ShopName,
      });

      AppLogger.d('✅ Updated chat room $chatRoomId with correct user data');
    } catch (e) {
      AppLogger.d('❌ Error updating chat room user data: $e');
    }
  }

  // Generate chat room ID from two user IDs
  String _generateChatRoomId(String userId1, String userId2) {
    final sortedIds = [userId1, userId2]..sort();
    return '${sortedIds[0]}_${sortedIds[1]}';
  }

  // Get or create a chat room between two users
  Future<String> getOrCreateChatRoom(String otherUserId, {
    String? productId,
    String? productName,
    String? productImage,
  }) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      final chatRoomId = _generateChatRoomId(currentUser.uid, otherUserId);
      final chatRoomRef = _database.ref('chatRooms/$chatRoomId');

      // Check if chat room already exists
      final snapshot = await chatRoomRef.get();
      
      if (!snapshot.exists) {
        // Get user data from Firestore
        final currentUserDoc = await _firestore.collection('User').doc(currentUser.uid).get();
        final otherUserDoc = await _firestore.collection('User').doc(otherUserId).get();

        String currentUserName = currentUserDoc.data()?['fullName'] ?? 
                                 currentUserDoc.data()?['displayName'] ?? 'User';
        String otherUserName = otherUserDoc.data()?['fullName'] ?? 
                               otherUserDoc.data()?['displayName'] ?? 'User';

        // Get user avatars from User collection
        String? currentUserAvatar = currentUserDoc.data()?['photoURL'];
        String? otherUserAvatar = otherUserDoc.data()?['photoURL'];

        // Check if users are sellers to get shop names and seller avatars
        String? currentUserShopName;
        String? otherUserShopName;

        if (currentUserDoc.data()?['role'] == 'seller') {
          final sellerDoc = await _firestore.collection('Seller').doc(currentUser.uid).get();
          currentUserShopName = sellerDoc.data()?['shopName'];
          // Use seller's photoURL if available, otherwise keep user's photoURL
          String? sellerPhotoURL = sellerDoc.data()?['photoURL'];
          if (sellerPhotoURL != null && sellerPhotoURL.isNotEmpty) {
            currentUserAvatar = sellerPhotoURL;
          }
        }

        if (otherUserDoc.data()?['role'] == 'seller') {
          final sellerDoc = await _firestore.collection('Seller').doc(otherUserId).get();
          otherUserShopName = sellerDoc.data()?['shopName'];
          // Use seller's photoURL if available, otherwise keep user's photoURL
          String? sellerPhotoURL = sellerDoc.data()?['photoURL'];
          if (sellerPhotoURL != null && sellerPhotoURL.isNotEmpty) {
            otherUserAvatar = sellerPhotoURL;
          }
        }

        // Create new chat room
        final chatRoom = ChatRoom(
          id: chatRoomId,
          user1Id: currentUser.uid,
          user2Id: otherUserId,
          user1Name: currentUserName,
          user2Name: otherUserName,
          user1Avatar: currentUserAvatar,
          user2Avatar: otherUserAvatar,
          user1ShopName: currentUserShopName,
          user2ShopName: otherUserShopName,
          lastActivity: DateTime.now(),
        );

        await chatRoomRef.set(chatRoom.toMap());

        // If this is a product inquiry, send initial product message
        if (productId != null && productName != null) {
          await sendMessage(
            chatRoomId: chatRoomId,
            receiverId: otherUserId,
            message: 'Hi! I\'m interested in this product.',
            productId: productId,
            productName: productName,
            productImage: productImage,
          );
        }
      }

      return chatRoomId;
    } catch (e) {
      AppLogger.d('❌ Error creating chat room: $e');
      throw Exception('Failed to create chat room: $e');
    }
  }

  // Send a message
  Future<void> sendMessage({
    required String chatRoomId,
    required String receiverId,
    required String message,
    String? productId,
    String? productName,
    String? productImage,
  }) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      // Get sender data
      final userDoc = await _firestore.collection('User').doc(currentUser.uid).get();
      final senderName = userDoc.data()?['fullName'] ?? 
                         userDoc.data()?['displayName'] ?? 'User';
      
      // Get sender avatar
      String? senderAvatar = userDoc.data()?['photoURL'];
      
      // If user is a seller, check for seller's photoURL
      if (userDoc.data()?['role'] == 'seller') {
        final sellerDoc = await _firestore.collection('Seller').doc(currentUser.uid).get();
        String? sellerPhotoURL = sellerDoc.data()?['photoURL'];
        if (sellerPhotoURL != null && sellerPhotoURL.isNotEmpty) {
          senderAvatar = sellerPhotoURL;
        }
      }

      final messageId = _database.ref('chatRooms/$chatRoomId/messages').push().key;
      
      if (messageId == null) {
        throw Exception('Failed to generate message ID');
      }

      final chatMessage = ChatMessage(
        id: messageId,
        senderId: currentUser.uid,
        receiverId: receiverId,
        message: message,
        timestamp: DateTime.now(),
        senderName: senderName,
        senderAvatar: senderAvatar,
        productId: productId,
        productName: productName,
        productImage: productImage,
      );

      // Add message to messages collection
      await _database.ref('chatRooms/$chatRoomId/messages/$messageId').set(chatMessage.toMap());

      // Update chat room with last message and activity
      await _database.ref('chatRooms/$chatRoomId').update({
        'lastMessage': chatMessage.toMap(),
        'lastActivity': DateTime.now().millisecondsSinceEpoch,
      });

      AppLogger.d('✅ Message sent successfully');
    } catch (e) {
      AppLogger.d('❌ Error sending message: $e');
      throw Exception('Failed to send message: $e');
    }
  }

  // Get messages stream for a chat room
  Stream<List<ChatMessage>> getMessagesStream(String chatRoomId) {
    return _database
        .ref('chatRooms/$chatRoomId/messages')
        .orderByChild('timestamp')
        .onValue
        .map((event) {
      final List<ChatMessage> messages = [];
      
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        data.forEach((key, value) {
          messages.add(ChatMessage.fromMap(key, value));
        });
      }
      
      // Sort by timestamp (newest last)
      messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return messages;
    });
  }

  // Get chat rooms stream for current user
  Stream<List<ChatRoom>> getChatRoomsStream() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return Stream.value([]);
    }

    return _database
        .ref('chatRooms')
        .orderByChild('lastActivity')
        .onValue
        .map((event) {
      final List<ChatRoom> chatRooms = [];
      
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        data.forEach((key, value) {
          final chatRoom = ChatRoom.fromMap(key, value);
          // Only include chat rooms where current user is a participant
          if (chatRoom.user1Id == currentUser.uid || chatRoom.user2Id == currentUser.uid) {
            chatRooms.add(chatRoom);
            
            // Check if chat room needs user data update (if names are still "User")
            if (chatRoom.user1Name == 'User' || chatRoom.user2Name == 'User' ||
                chatRoom.user1Name.isEmpty || chatRoom.user2Name.isEmpty) {
              // Update chat room data in the background
              updateChatRoomUserData(key, chatRoom.user1Id, chatRoom.user2Id);
            }
          }
        });
      }
      
      // Sort by last activity (newest first)
      chatRooms.sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
      return chatRooms;
    });
  }

  // Mark messages as read
  Future<void> markMessagesAsRead(String chatRoomId, String senderId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final messagesRef = _database.ref('chatRooms/$chatRoomId/messages');
      final snapshot = await messagesRef.orderByChild('receiverId').equalTo(currentUser.uid).get();
      
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final updates = <String, dynamic>{};
        
        data.forEach((key, value) {
          if (value['isRead'] != true && value['senderId'] == senderId) {
            updates['$key/isRead'] = true;
          }
        });
        
        if (updates.isNotEmpty) {
          await messagesRef.update(updates);
        }
      }
    } catch (e) {
      AppLogger.d('❌ Error marking messages as read: $e');
    }
  }

  // Delete a chat room
  Future<void> deleteChatRoom(String chatRoomId) async {
    try {
      await _database.ref('chatRooms/$chatRoomId').remove();
      AppLogger.d('✅ Chat room deleted successfully');
    } catch (e) {
      AppLogger.d('❌ Error deleting chat room: $e');
      throw Exception('Failed to delete chat room: $e');
    }
  }
}
