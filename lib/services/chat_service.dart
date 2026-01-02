import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:dentpal/utils/app_logger.dart';

/// Exception thrown when a CSR tries to lock a chat that is already locked by another CSR
class ChatLockConflictException implements Exception {
  final String message;
  final String? lockedByCsrId;
  final String? lockedByCsrName;

  ChatLockConflictException({
    required this.message,
    this.lockedByCsrId,
    this.lockedByCsrName,
  });

  @override
  String toString() => message;
}

/// Exception thrown when an invalid Firebase path key is detected
class InvalidFirebaseKeyException implements Exception {
  final String message;
  final String invalidKey;
  final String? invalidCharacters;

  InvalidFirebaseKeyException({
    required this.message,
    required this.invalidKey,
    this.invalidCharacters,
  });

  @override
  String toString() => message;
}

/// Validates that a string is safe to use as a Firebase Realtime Database path key.
/// Firebase RTDB keys cannot contain: . # $ [ ] /
///
/// Throws [InvalidFirebaseKeyException] if the key contains illegal characters.
/// Returns the validated key if valid.
String validateFirebaseKey(String key, {String fieldName = 'key'}) {
  if (key.isEmpty) {
    throw InvalidFirebaseKeyException(
      message: '$fieldName cannot be empty',
      invalidKey: key,
    );
  }

  // Firebase RTDB illegal characters for keys
  const illegalChars = ['.', '#', '\$', '[', ']', '/'];
  final foundIllegal = <String>[];

  for (final char in illegalChars) {
    if (key.contains(char)) {
      foundIllegal.add(char);
    }
  }

  if (foundIllegal.isNotEmpty) {
    throw InvalidFirebaseKeyException(
      message:
          '$fieldName contains illegal Firebase characters: ${foundIllegal.join(', ')}. '
          'Firebase Realtime Database keys cannot contain . # \$ [ ] /',
      invalidKey: key,
      invalidCharacters: foundIllegal.join(''),
    );
  }

  return key;
}

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
  final String? productId;
  final String? productName;
  final String? productImage;
  final String? sellerId; // The seller in this chat room
  final List<String>
  deletedFor; // Users who have "deleted" this chat (one-sided)

  // Support chat fields
  final bool
  isSupportChat; // True if this is a customer support chat (created from order details)
  final String? orderId; // Order ID if this is an order-related support chat
  final String? lockedByCsrId; // CSR user ID who locked this chat
  final String? lockedByCsrName; // CSR name who locked this chat
  final DateTime? lockedAt; // When the chat was locked

  // Support requested fields (for buyer/seller chats that need CSR help)
  final bool
  supportRequested; // True if buyer/seller requested support in this chat
  final String? csrId; // CSR user ID who joined this chat
  final String? csrName; // CSR name who joined this chat

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
    this.productId,
    this.productName,
    this.productImage,
    this.sellerId,
    this.deletedFor = const [],
    this.isSupportChat = false,
    this.orderId,
    this.lockedByCsrId,
    this.lockedByCsrName,
    this.lockedAt,
    this.supportRequested = false,
    this.csrId,
    this.csrName,
  });

  factory ChatRoom.fromMap(String id, Map<dynamic, dynamic> data) {
    ChatMessage? lastMessage;
    if (data['lastMessage'] != null) {
      lastMessage = ChatMessage.fromMap('last', data['lastMessage']);
    }

    // Parse deletedFor list
    List<String> deletedFor = [];
    if (data['deletedFor'] != null) {
      if (data['deletedFor'] is List) {
        deletedFor = List<String>.from(data['deletedFor']);
      } else if (data['deletedFor'] is Map) {
        // Handle case where Firebase stores it as a map
        deletedFor = (data['deletedFor'] as Map).values.cast<String>().toList();
      }
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
      lastActivity: DateTime.fromMillisecondsSinceEpoch(
        data['lastActivity'] ?? 0,
      ),
      unreadCount: data['unreadCount'] ?? 0,
      productId: data['productId'],
      productName: data['productName'],
      productImage: data['productImage'],
      sellerId: data['sellerId'],
      deletedFor: deletedFor,
      isSupportChat: data['isSupportChat'] ?? false,
      orderId: data['orderId'],
      lockedByCsrId: data['lockedByCsrId'],
      lockedByCsrName: data['lockedByCsrName'],
      lockedAt: data['lockedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['lockedAt'])
          : null,
      supportRequested: data['supportRequested'] ?? false,
      csrId: data['csrId'],
      csrName: data['csrName'],
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
      'productId': productId,
      'productName': productName,
      'productImage': productImage,
      'sellerId': sellerId,
      'deletedFor': deletedFor,
      'isSupportChat': isSupportChat,
      'orderId': orderId,
      'lockedByCsrId': lockedByCsrId,
      'lockedByCsrName': lockedByCsrName,
      'lockedAt': lockedAt?.millisecondsSinceEpoch,
      'supportRequested': supportRequested,
      'csrId': csrId,
      'csrName': csrName,
    };
  }

  // Check if chat is locked by a CSR
  bool get isLocked => lockedByCsrId != null;

  // Check if a CSR has joined this chat
  bool get hasCsrJoined => csrId != null;

  // Check if this CSR can message in this chat (for support chats or chats with support requested)
  bool canCsrMessage(String csrId) {
    // For dedicated support chats (from order details)
    if (isSupportChat) {
      if (!isLocked) return true; // Any CSR can message if not locked
      return lockedByCsrId == csrId; // Only the locking CSR can message
    }
    // For buyer/seller chats with support requested
    if (supportRequested) {
      if (!isLocked) return true; // Any CSR can message if not locked
      return lockedByCsrId == csrId; // Only the locking CSR can message
    }
    return false;
  }

  // Check if chat is deleted for a specific user
  bool isDeletedFor(String userId) {
    return deletedFor.contains(userId);
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

  // Get subtitle - for buyers show product name, for sellers show buyer name
  String? getDisplaySubtitle(String currentUserId) {
    // If current user is the seller, show product name as subtitle
    if (sellerId == currentUserId &&
        productName != null &&
        productName!.isNotEmpty) {
      return productName;
    }
    // For buyers, no subtitle needed (shop name is already the main display)
    return null;
  }

  // Check if the current user is the seller in this chat
  bool isCurrentUserSeller(String currentUserId) {
    return sellerId == currentUserId;
  }

  // Check if this is a product-specific chat
  bool get isProductChat => productId != null && productId!.isNotEmpty;
}

class ChatService {
  static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;

  late final FirebaseDatabase _database;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  ChatService._internal() {
    _database = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          'https://dentpal-161e5-default-rtdb.asia-southeast1.firebasedatabase.app/',
    );
  }

  // Update existing chat room with correct user names
  Future<void> updateChatRoomUserData(
    String chatRoomId,
    String user1Id,
    String user2Id,
  ) async {
    try {
      final chatRoomRef = _database.ref('chatRooms/$chatRoomId');

      // Get user data from Firestore
      final user1Doc = await _firestore.collection('User').doc(user1Id).get();
      final user2Doc = await _firestore.collection('User').doc(user2Id).get();

      String user1Name =
          user1Doc.data()?['fullName'] ??
          user1Doc.data()?['displayName'] ??
          'User';
      String user2Name =
          user2Doc.data()?['fullName'] ??
          user2Doc.data()?['displayName'] ??
          'User';

      // Get user avatars from User collection
      String? user1Avatar = user1Doc.data()?['photoURL'];
      String? user2Avatar = user2Doc.data()?['photoURL'];

      // Check if users are sellers to get shop names and seller avatars
      String? user1ShopName;
      String? user2ShopName;

      if (user1Doc.data()?['role'] == 'seller') {
        final sellerDoc = await _firestore
            .collection('Seller')
            .doc(user1Id)
            .get();
        user1ShopName = sellerDoc.data()?['shopName'];
        // Use seller's photoURL if available, otherwise keep user's photoURL
        String? sellerPhotoURL = sellerDoc.data()?['photoURL'];
        if (sellerPhotoURL != null && sellerPhotoURL.isNotEmpty) {
          user1Avatar = sellerPhotoURL;
        }
      }

      if (user2Doc.data()?['role'] == 'seller') {
        final sellerDoc = await _firestore
            .collection('Seller')
            .doc(user2Id)
            .get();
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

      AppLogger.d('Updated chat room $chatRoomId with correct user data');
    } catch (e) {
      AppLogger.d('Error updating chat room user data: $e');
    }
  }

  // Generate chat room ID from two user IDs and optional product ID
  String _generateChatRoomId(
    String userId1,
    String userId2, {
    String? productId,
    String? orderId,
  }) {
    final sortedIds = [userId1, userId2]..sort();

    // Order-specific chat room (highest priority)
    if (orderId != null && orderId.isNotEmpty) {
      return '${sortedIds[0]}_${sortedIds[1]}_order_$orderId';
    }

    // Product-specific chat room
    if (productId != null && productId.isNotEmpty) {
      return '${sortedIds[0]}_${sortedIds[1]}_$productId';
    }

    // General chat room (no product or order)
    return '${sortedIds[0]}_${sortedIds[1]}';
  }

  // Get or create a chat room between two users (product-specific if productId provided)
  Future<String> getOrCreateChatRoom(
    String otherUserId, {
    String? productId,
    String? productName,
    String? productImage,
    String? orderId,
    DateTime? orderDate,
  }) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      // Generate chat room ID (includes productId if provided for product-specific chats)
      final chatRoomId = _generateChatRoomId(
        currentUser.uid,
        otherUserId,
        productId: productId,
        orderId: orderId,
      );
      final chatRoomRef = _database.ref('chatRooms/$chatRoomId');

      // Check if chat room already exists
      final snapshot = await chatRoomRef.get();

      if (!snapshot.exists) {
        // Get user data from Firestore
        final currentUserDoc = await _firestore
            .collection('User')
            .doc(currentUser.uid)
            .get();
        final otherUserDoc = await _firestore
            .collection('User')
            .doc(otherUserId)
            .get();

        String currentUserName =
            currentUserDoc.data()?['fullName'] ??
            currentUserDoc.data()?['displayName'] ??
            'User';
        String otherUserName =
            otherUserDoc.data()?['fullName'] ??
            otherUserDoc.data()?['displayName'] ??
            'User';

        // Get user avatars from User collection
        String? currentUserAvatar = currentUserDoc.data()?['photoURL'];
        String? otherUserAvatar = otherUserDoc.data()?['photoURL'];

        // Check if users are sellers to get shop names and seller avatars
        String? currentUserShopName;
        String? otherUserShopName;
        String? sellerId;

        if (currentUserDoc.data()?['role'] == 'seller') {
          final sellerDoc = await _firestore
              .collection('Seller')
              .doc(currentUser.uid)
              .get();
          currentUserShopName = sellerDoc.data()?['shopName'];
          sellerId = currentUser.uid;
          // Use seller's photoURL if available, otherwise keep user's photoURL
          String? sellerPhotoURL = sellerDoc.data()?['photoURL'];
          if (sellerPhotoURL != null && sellerPhotoURL.isNotEmpty) {
            currentUserAvatar = sellerPhotoURL;
          }
        }

        if (otherUserDoc.data()?['role'] == 'seller') {
          final sellerDoc = await _firestore
              .collection('Seller')
              .doc(otherUserId)
              .get();
          otherUserShopName = sellerDoc.data()?['shopName'];
          sellerId = otherUserId;
          // Use seller's photoURL if available, otherwise keep user's photoURL
          String? sellerPhotoURL = sellerDoc.data()?['photoURL'];
          if (sellerPhotoURL != null && sellerPhotoURL.isNotEmpty) {
            otherUserAvatar = sellerPhotoURL;
          }
        }

        // Create new chat room with product info
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
          productId: productId,
          productName: productName,
          productImage: productImage,
          sellerId: sellerId,
          orderId: orderId,
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

        // If this is an order-related chat, send initial order help message
        if (orderId != null) {
          await sendMessage(
            chatRoomId: chatRoomId,
            receiverId: otherUserId,
            message: 'I need help with my order: $orderId',
          );
        }
      }

      return chatRoomId;
    } catch (e) {
      AppLogger.d('Error creating chat room: $e');
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
      final userDoc = await _firestore
          .collection('User')
          .doc(currentUser.uid)
          .get();
      final senderName =
          userDoc.data()?['fullName'] ??
          userDoc.data()?['displayName'] ??
          'User';

      // Get sender avatar
      String? senderAvatar = userDoc.data()?['photoURL'];

      // If user is a seller, check for seller's photoURL
      if (userDoc.data()?['role'] == 'seller') {
        final sellerDoc = await _firestore
            .collection('Seller')
            .doc(currentUser.uid)
            .get();
        String? sellerPhotoURL = sellerDoc.data()?['photoURL'];
        if (sellerPhotoURL != null && sellerPhotoURL.isNotEmpty) {
          senderAvatar = sellerPhotoURL;
        }
      }

      final messageId = _database
          .ref('chatRooms/$chatRoomId/messages')
          .push()
          .key;

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
      await _database
          .ref('chatRooms/$chatRoomId/messages/$messageId')
          .set(chatMessage.toMap());

      // Update chat room with last message and activity
      await _database.ref('chatRooms/$chatRoomId').update({
        'lastMessage': chatMessage.toMap(),
        'lastActivity': DateTime.now().millisecondsSinceEpoch,
      });

      AppLogger.d('Message sent successfully');
    } catch (e) {
      AppLogger.d('Error sending message: $e');
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

    return _database.ref('chatRooms').orderByChild('lastActivity').onValue.map((
      event,
    ) {
      final List<ChatRoom> chatRooms = [];

      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        data.forEach((key, value) {
          final chatRoom = ChatRoom.fromMap(key, value);
          // Only include chat rooms where current user is a participant
          // AND chat is not deleted for this user
          if ((chatRoom.user1Id == currentUser.uid ||
                  chatRoom.user2Id == currentUser.uid) &&
              !chatRoom.isDeletedFor(currentUser.uid)) {
            chatRooms.add(chatRoom);

            // Check if chat room needs user data update (if names are still "User")
            if (chatRoom.user1Name == 'User' ||
                chatRoom.user2Name == 'User' ||
                chatRoom.user1Name.isEmpty ||
                chatRoom.user2Name.isEmpty) {
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
      final snapshot = await messagesRef
          .orderByChild('receiverId')
          .equalTo(currentUser.uid)
          .get();

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
      AppLogger.d('Error marking messages as read: $e');
    }
  }

  // Delete a chat room (one-sided - only hides for current user)
  Future<void> deleteChatRoom(String chatRoomId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      final chatRoomRef = _database.ref('chatRooms/$chatRoomId');
      final snapshot = await chatRoomRef.get();

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;

        // Get existing deletedFor list
        List<String> deletedFor = [];
        if (data['deletedFor'] != null) {
          if (data['deletedFor'] is List) {
            deletedFor = List<String>.from(data['deletedFor']);
          } else if (data['deletedFor'] is Map) {
            deletedFor = (data['deletedFor'] as Map).values
                .cast<String>()
                .toList();
          }
        }

        // Add current user to deletedFor if not already there
        if (!deletedFor.contains(currentUser.uid)) {
          deletedFor.add(currentUser.uid);
        }

        // Update the chat room with the new deletedFor list
        await chatRoomRef.update({'deletedFor': deletedFor});

        AppLogger.d('Chat room hidden for user ${currentUser.uid}');
      }
    } catch (e) {
      AppLogger.d('Error hiding chat room: $e');
      throw Exception('Failed to hide chat room: $e');
    }
  }

  // Restore a deleted chat room for current user (unhide)
  Future<void> restoreChatRoom(String chatRoomId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      final chatRoomRef = _database.ref('chatRooms/$chatRoomId');
      final snapshot = await chatRoomRef.get();

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;

        // Get existing deletedFor list
        List<String> deletedFor = [];
        if (data['deletedFor'] != null) {
          if (data['deletedFor'] is List) {
            deletedFor = List<String>.from(data['deletedFor']);
          } else if (data['deletedFor'] is Map) {
            deletedFor = (data['deletedFor'] as Map).values
                .cast<String>()
                .toList();
          }
        }

        // Remove current user from deletedFor
        deletedFor.remove(currentUser.uid);

        // Update the chat room with the new deletedFor list
        await chatRoomRef.update({'deletedFor': deletedFor});

        AppLogger.d('Chat room restored for user ${currentUser.uid}');
      }
    } catch (e) {
      AppLogger.d('Error restoring chat room: $e');
      throw Exception('Failed to restore chat room: $e');
    }
  }

  // ==================== SUPPORT CHAT METHODS ====================

  // Create a support chat room for an order
  // This creates a chat visible to all CSR accounts
  Future<String> createSupportChatRoom({
    required String orderId,
    required String orderNumber,
  }) async {
    try {
      // Validate orderId before using in Firebase path
      validateFirebaseKey(orderId, fieldName: 'orderId');

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      // Generate support chat room ID using order ID (validated above)
      final chatRoomId = 'support_$orderId';
      final chatRoomRef = _database.ref('chatRooms/$chatRoomId');

      // Check if support chat already exists for this order
      final snapshot = await chatRoomRef.get();

      if (snapshot.exists) {
        // Support chat already exists, return the existing chat room ID
        AppLogger.d('Support chat already exists for order $orderId');
        return chatRoomId;
      }

      // Get current user data from Firestore
      final currentUserDoc = await _firestore
          .collection('User')
          .doc(currentUser.uid)
          .get();

      String currentUserName =
          currentUserDoc.data()?['fullName'] ??
          currentUserDoc.data()?['displayName'] ??
          'User';
      String? currentUserAvatar = currentUserDoc.data()?['photoURL'];

      // Create new support chat room
      // user1 = customer, user2 = "Customer Support" (placeholder for CSR)
      final chatRoom = ChatRoom(
        id: chatRoomId,
        user1Id: currentUser.uid,
        user2Id: 'customer_support', // Placeholder ID for support team
        user1Name: currentUserName,
        user2Name: 'Customer Support',
        user1Avatar: currentUserAvatar,
        user2Avatar: null,
        lastActivity: DateTime.now(),
        isSupportChat: true,
        orderId: orderId,
      );

      await chatRoomRef.set(chatRoom.toMap());

      // Send initial message about the order
      await _sendSupportMessage(
        chatRoomId: chatRoomId,
        senderId: currentUser.uid,
        senderName: currentUserName,
        senderAvatar: currentUserAvatar,
        message: 'Hi! I need help with my order #$orderNumber.',
      );

      AppLogger.d('Support chat created for order $orderId');
      return chatRoomId;
    } catch (e) {
      AppLogger.d('Error creating support chat room: $e');
      throw Exception('Failed to create support chat room: $e');
    }
  }

  // Internal method to send support messages
  Future<void> _sendSupportMessage({
    required String chatRoomId,
    required String senderId,
    required String senderName,
    String? senderAvatar,
    required String message,
  }) async {
    final messageId = _database
        .ref('chatRooms/$chatRoomId/messages')
        .push()
        .key;

    if (messageId == null) {
      throw Exception('Failed to generate message ID');
    }

    final chatMessage = ChatMessage(
      id: messageId,
      senderId: senderId,
      receiverId: 'customer_support', // Messages to support team
      message: message,
      timestamp: DateTime.now(),
      senderName: senderName,
      senderAvatar: senderAvatar,
    );

    // Add message to messages collection
    await _database
        .ref('chatRooms/$chatRoomId/messages/$messageId')
        .set(chatMessage.toMap());

    // Update chat room with last message and activity
    await _database.ref('chatRooms/$chatRoomId').update({
      'lastMessage': chatMessage.toMap(),
      'lastActivity': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // Send a message in a support chat (with locking check for CSR)
  Future<void> sendSupportMessage({
    required String chatRoomId,
    required String message,
    bool isFromCsr = false,
    String? csrId,
    String? csrName,
  }) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      if (isFromCsr) {
        // Use atomic transaction to check and acquire lock
        await _tryAcquireCsrLock(
          chatRoomId: chatRoomId,
          csrId: currentUser.uid,
          csrName: csrName ?? 'Support Agent',
        );
      }

      // Get sender data
      final userDoc = await _firestore
          .collection('User')
          .doc(currentUser.uid)
          .get();
      final senderName =
          userDoc.data()?['fullName'] ??
          userDoc.data()?['displayName'] ??
          'User';
      String? senderAvatar = userDoc.data()?['photoURL'];

      await _sendSupportMessage(
        chatRoomId: chatRoomId,
        senderId: currentUser.uid,
        senderName: isFromCsr ? (csrName ?? senderName) : senderName,
        senderAvatar: senderAvatar,
        message: message,
      );

      AppLogger.d('Support message sent successfully');
    } catch (e) {
      AppLogger.d('Error sending support message: $e');
      rethrow;
    }
  }

  /// Atomically checks and acquires a lock on a support chat for a CSR.
  /// Uses Firebase transaction to prevent TOCTOU race conditions.
  ///
  /// Throws [ChatLockConflictException] if the chat is locked by another CSR.
  /// Throws [Exception] if the chat room is not found.
  Future<void> _tryAcquireCsrLock({
    required String chatRoomId,
    required String csrId,
    required String csrName,
  }) async {
    final chatRoomRef = _database.ref('chatRooms/$chatRoomId');

    final result = await chatRoomRef.runTransaction((currentData) {
      if (currentData == null) {
        // Chat room doesn't exist, abort transaction
        return Transaction.abort();
      }

      final data = Map<String, dynamic>.from(currentData as Map);
      final lockedByCsrId = data['lockedByCsrId'] as String?;

      // Check if already locked by this CSR (allow through)
      if (lockedByCsrId == csrId) {
        // Already locked by this CSR, no changes needed
        return Transaction.success(currentData);
      }

      // Check if locked by another CSR
      if (lockedByCsrId != null && lockedByCsrId.isNotEmpty) {
        // Locked by another CSR, abort transaction
        // We'll handle this case after the transaction
        return Transaction.abort();
      }

      // Not locked, acquire the lock atomically
      data['lockedByCsrId'] = csrId;
      data['lockedByCsrName'] = csrName;
      data['lockedAt'] = DateTime.now().millisecondsSinceEpoch;

      // For dedicated support chats (not support requested), also set user2
      final isSupportChat = data['isSupportChat'] == true;
      final supportRequested = data['supportRequested'] == true;

      if (isSupportChat && !supportRequested) {
        data['user2Id'] = csrId;
        data['user2Name'] = csrName;
      }

      // For support requested chats, also set csrId and csrName
      if (supportRequested) {
        data['csrId'] = csrId;
        data['csrName'] = csrName;
      }

      return Transaction.success(data);
    });

    if (!result.committed) {
      // Transaction was aborted - either room doesn't exist or locked by another CSR
      // Re-read to determine the reason
      final snapshot = await chatRoomRef.get();

      if (!snapshot.exists) {
        throw Exception('Chat room not found');
      }

      final data = Map<String, dynamic>.from(snapshot.value as Map);
      final lockedByCsrId = data['lockedByCsrId'] as String?;
      final lockedByCsrName = data['lockedByCsrName'] as String?;

      if (lockedByCsrId != null &&
          lockedByCsrId.isNotEmpty &&
          lockedByCsrId != csrId) {
        throw ChatLockConflictException(
          message:
              'This conversation is locked by another support agent${lockedByCsrName != null ? ' ($lockedByCsrName)' : ''}',
          lockedByCsrId: lockedByCsrId,
          lockedByCsrName: lockedByCsrName,
        );
      }

      // If we get here, something unexpected happened
      throw Exception('Failed to acquire lock on chat room');
    }

    AppLogger.d('CSR $csrId acquired lock on chat $chatRoomId');
  }

  // Lock a support chat to a specific CSR (uses atomic transaction)
  // Throws [ChatLockConflictException] if already locked by another CSR.
  Future<void> lockSupportChat({
    required String chatRoomId,
    required String csrId,
    required String csrName,
  }) async {
    try {
      await _tryAcquireCsrLock(
        chatRoomId: chatRoomId,
        csrId: csrId,
        csrName: csrName,
      );
      AppLogger.d('Support chat $chatRoomId locked by CSR $csrId');
    } catch (e) {
      AppLogger.d('Error locking support chat: $e');
      rethrow;
    }
  }

  // Unlock a support chat (only by the CSR who locked it)
  Future<void> unlockSupportChat({required String chatRoomId}) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      final chatRoomRef = _database.ref('chatRooms/$chatRoomId');
      final snapshot = await chatRoomRef.get();

      if (!snapshot.exists) {
        throw Exception('Chat room not found');
      }

      final chatRoom = ChatRoom.fromMap(
        chatRoomId,
        snapshot.value as Map<dynamic, dynamic>,
      );

      // Only the CSR who locked can unlock
      if (chatRoom.lockedByCsrId != currentUser.uid) {
        throw Exception(
          'Only the support agent who locked this chat can unlock it',
        );
      }

      // Base update for unlocking
      final Map<String, dynamic> updates = {
        'lockedByCsrId': null,
        'lockedByCsrName': null,
        'lockedAt': null,
      };

      // Only reset user2 for dedicated support chats (not support requested)
      if (chatRoom.isSupportChat && !chatRoom.supportRequested) {
        updates['user2Id'] = 'customer_support';
        updates['user2Name'] = 'Customer Support';
      }

      // Note: We don't clear csrId/csrName for support requested chats
      // because the CSR is still part of the conversation

      await chatRoomRef.update(updates);

      AppLogger.d('Support chat $chatRoomId unlocked');
    } catch (e) {
      AppLogger.d('Error unlocking support chat: $e');
      throw Exception('Failed to unlock support chat: $e');
    }
  }

  // Get all support chat rooms stream (for CSR accounts)
  // Includes both dedicated support chats AND regular chats with support requested
  Stream<List<ChatRoom>> getSupportChatRoomsStream() {
    return _database.ref('chatRooms').orderByChild('lastActivity').onValue.map((
      event,
    ) {
      final List<ChatRoom> supportChats = [];

      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        data.forEach((key, value) {
          final chatRoom = ChatRoom.fromMap(key, value);
          // Include dedicated support chats OR chats where support was requested
          if (chatRoom.isSupportChat || chatRoom.supportRequested) {
            supportChats.add(chatRoom);
          }
        });
      }

      // Sort by last activity (newest first)
      supportChats.sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
      return supportChats;
    });
  }

  // Request support for an existing chat room (buyer/seller can call this)
  Future<void> requestSupportForChat({required String chatRoomId}) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      final chatRoomRef = _database.ref('chatRooms/$chatRoomId');
      final snapshot = await chatRoomRef.get();

      if (!snapshot.exists) {
        throw Exception('Chat room not found');
      }

      final chatRoom = ChatRoom.fromMap(
        chatRoomId,
        snapshot.value as Map<dynamic, dynamic>,
      );

      // Check if support already requested or CSR already joined
      if (chatRoom.supportRequested || chatRoom.hasCsrJoined) {
        throw Exception('Support has already been requested for this chat');
      }

      // Get requester info
      final userDoc = await _firestore
          .collection('User')
          .doc(currentUser.uid)
          .get();
      final requesterName =
          userDoc.data()?['fullName'] ??
          userDoc.data()?['displayName'] ??
          'User';

      // Update chat room to request support
      await chatRoomRef.update({'supportRequested': true});

      // Send a system message about support request
      await _sendSupportMessage(
        chatRoomId: chatRoomId,
        senderId: 'system',
        senderName: 'System',
        message:
            '$requesterName has requested customer support. A support agent will join this conversation shortly.',
      );

      AppLogger.d('Support requested for chat $chatRoomId');
    } catch (e) {
      AppLogger.d('Error requesting support: $e');
      rethrow;
    }
  }

  // CSR joins a chat that has support requested
  Future<void> joinChatAsSupport({
    required String chatRoomId,
    required String csrId,
    required String csrName,
  }) async {
    try {
      final chatRoomRef = _database.ref('chatRooms/$chatRoomId');
      final snapshot = await chatRoomRef.get();

      if (!snapshot.exists) {
        throw Exception('Chat room not found');
      }

      final chatRoom = ChatRoom.fromMap(
        chatRoomId,
        snapshot.value as Map<dynamic, dynamic>,
      );

      // Only allow joining chats that need support
      if (!chatRoom.isSupportChat && !chatRoom.supportRequested) {
        throw Exception('This chat has not requested support');
      }

      // Check if another CSR already joined
      if (chatRoom.hasCsrJoined && chatRoom.csrId != csrId) {
        throw Exception('Another support agent has already joined this chat');
      }

      // Update chat room with CSR info and lock it
      await chatRoomRef.update({
        'csrId': csrId,
        'csrName': csrName,
        'lockedByCsrId': csrId,
        'lockedByCsrName': csrName,
        'lockedAt': DateTime.now().millisecondsSinceEpoch,
      });

      // Send a system message about CSR joining
      await _sendSupportMessage(
        chatRoomId: chatRoomId,
        senderId: 'system',
        senderName: 'System',
        message: '$csrName from Customer Support has joined the conversation.',
      );

      AppLogger.d('CSR $csrId joined chat $chatRoomId');
    } catch (e) {
      AppLogger.d('Error joining chat as support: $e');
      rethrow;
    }
  }

  // Get chat room by ID
  Future<ChatRoom?> getChatRoom(String chatRoomId) async {
    try {
      final chatRoomRef = _database.ref('chatRooms/$chatRoomId');
      final snapshot = await chatRoomRef.get();

      if (snapshot.exists) {
        return ChatRoom.fromMap(
          chatRoomId,
          snapshot.value as Map<dynamic, dynamic>,
        );
      }
      return null;
    } catch (e) {
      AppLogger.d('Error getting chat room: $e');
      return null;
    }
  }

  // Get support chat room for a specific order (for customer)
  Future<ChatRoom?> getSupportChatForOrder(String orderId) async {
    try {
      // Validate orderId before using in Firebase path
      validateFirebaseKey(orderId, fieldName: 'orderId');

      final chatRoomId = 'support_$orderId';
      final chatRoomRef = _database.ref('chatRooms/$chatRoomId');
      final snapshot = await chatRoomRef.get();

      if (snapshot.exists) {
        return ChatRoom.fromMap(
          chatRoomId,
          snapshot.value as Map<dynamic, dynamic>,
        );
      }
      return null;
    } catch (e) {
      AppLogger.d('Error getting support chat for order: $e');
      rethrow;
    }
  }

  // Check if current user is a CSR
  Future<bool> isCurrentUserCsr() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return false;

      final userDoc = await _firestore
          .collection('User')
          .doc(currentUser.uid)
          .get();

      return userDoc.data()?['role'] == 'customer_support';
    } catch (e) {
      AppLogger.d('Error checking CSR status: $e');
      return false;
    }
  }
}
