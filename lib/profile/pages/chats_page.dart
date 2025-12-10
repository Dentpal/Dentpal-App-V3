import 'package:dentpal/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dentpal/core/app_theme/index.dart';
import 'package:dentpal/services/chat_service.dart';
import 'package:dentpal/product/services/user_service.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'chat_detail_page.dart';

class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key});

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  final ChatService _chatService = ChatService();
  final UserService _userService = UserService();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isCurrentUserSeller = false;
  bool _isCurrentUserCsr = false;
  bool _isLoadingUserRole = true;

  @override
  void initState() {
    super.initState();
    _checkUserRole();
  }

  Future<void> _checkUserRole() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      try {
        final isSeller = await _userService.isCurrentUserSeller();
        final isCsr = await _userService.isCurrentUserCustomerSupport();
        if (mounted) {
          setState(() {
            _isCurrentUserSeller = isSeller;
            _isCurrentUserCsr = isCsr;
            _isLoadingUserRole = false;
          });
        }
      } catch (e) {
        AppLogger.d('Failed to check user role: $e');
        if (mounted) {
          setState(() {
            _isCurrentUserSeller = false;
            _isCurrentUserCsr = false;
            _isLoadingUserRole = false;
          });
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _isCurrentUserSeller = false;
          _isCurrentUserCsr = false;
          _isLoadingUserRole = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Chats'),
          backgroundColor: AppColors.surface,
          elevation: 0,
        ),
        body: const Center(child: Text('Please login to view chats')),
      );
    }

    // Show loading while checking user role
    if (_isLoadingUserRole) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(
            'Chats',
            style: AppTextStyles.titleLarge.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.onSurface,
            ),
          ),
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Chats',
          style: AppTextStyles.titleLarge.copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.onSurface,
          ),
        ),
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            padding: const EdgeInsets.all(16),
            color: AppColors.surface,
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
              },
              decoration: InputDecoration(
                hintText: 'Search chats...',
                hintStyle: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.onSurface.withValues(alpha: 0.5),
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: AppColors.onSurface.withValues(alpha: 0.5),
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.clear,
                          color: AppColors.onSurface.withValues(alpha: 0.5),
                        ),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppColors.primary, width: 2),
                ),
              ),
            ),
          ),

          // Chat list
          Expanded(
            child: StreamBuilder<List<ChatRoom>>(
              // CSR users see support chats, others see regular chats
              stream: _isCurrentUserCsr 
                  ? _chatService.getSupportChatRoomsStream()
                  : _chatService.getChatRoomsStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 64,
                          color: AppColors.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Error loading chats',
                          style: AppTextStyles.titleMedium.copyWith(
                            color: AppColors.error,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          snapshot.error.toString(),
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.onSurface.withValues(alpha: 0.7),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                final chatRooms = snapshot.data ?? [];

                // Filter chat rooms based on search query
                final filteredChatRooms = chatRooms.where((chatRoom) {
                  if (_searchQuery.isEmpty) return true;

                  final displayName = chatRoom
                      .getDisplayName(currentUser.uid)
                      .toLowerCase();
                  final subtitle =
                      chatRoom
                          .getDisplaySubtitle(currentUser.uid)
                          ?.toLowerCase() ??
                      '';
                  final productName = chatRoom.productName?.toLowerCase() ?? '';

                  return displayName.contains(_searchQuery) ||
                      subtitle.contains(_searchQuery) ||
                      productName.contains(_searchQuery);
                }).toList();

                if (filteredChatRooms.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _searchQuery.isNotEmpty
                                ? Icons.search_off
                                : Icons.chat_bubble_outline,
                            size: 64,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          _searchQuery.isNotEmpty
                              ? 'No chats found'
                              : 'No chats yet',
                          style: AppTextStyles.titleMedium.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _searchQuery.isNotEmpty
                              ? 'Try a different search term'
                              : 'Start a conversation by inquiring about a product',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.onSurface.withValues(alpha: 0.7),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                return _buildChatList(filteredChatRooms, currentUser.uid);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatList(List<ChatRoom> chatRooms, String currentUserId) {
    if (_isCurrentUserCsr) {
      // For CSR: Show support chat list
      return _buildCsrChatList(chatRooms, currentUserId);
    } else if (_isCurrentUserSeller) {
      // For sellers: Show each chat room separately with product info
      // Group by buyer, then show each product inquiry
      return _buildSellerChatList(chatRooms, currentUserId);
    } else {
      // For buyers: Group chats by seller (shop) with expandable product inquiries
      // Same experience as sellers but grouped by seller instead of buyer
      return _buildBuyerChatList(chatRooms, currentUserId);
    }
  }

  // CSR view: Show all support chats with lock status
  Widget _buildCsrChatList(List<ChatRoom> chatRooms, String currentUserId) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: chatRooms.length,
      itemBuilder: (context, index) {
        final chatRoom = chatRooms[index];
        return _buildSupportChatTile(chatRoom, currentUserId);
      },
    );
  }

  Widget _buildSupportChatTile(ChatRoom chatRoom, String currentUserId) {
    // For dedicated support chats, customer is user1
    // For support requested chats, show both users (buyer and seller)
    final isDedicatedSupport = chatRoom.isSupportChat;
    final customerName = isDedicatedSupport 
        ? chatRoom.user1Name 
        : '${chatRoom.user1Name} & ${chatRoom.user2Name}';
    final lastMessage = chatRoom.lastMessage;
    final isLocked = chatRoom.isLocked;
    final lockedByMe = chatRoom.lockedByCsrId == currentUserId;
    
    // Check if CSR has joined (for support requested chats)
    final csrHasJoined = chatRoom.hasCsrJoined;
    
    return Dismissible(
      key: Key(chatRoom.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppColors.error,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        return await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Chat'),
            content: const Text('Are you sure you want to delete this chat?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
      },
      onDismissed: (direction) async {
        try {
          await _chatService.deleteChatRoom(chatRoom.id);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Chat deleted')),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to delete chat: $e')),
            );
          }
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Stack(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                backgroundImage: chatRoom.user1Avatar != null
                    ? CachedNetworkImageProvider(chatRoom.user1Avatar!)
                    : null,
                child: chatRoom.user1Avatar == null
                    ? Icon(Icons.person, color: AppColors.primary, size: 28)
                    : null,
              ),
              // Lock indicator
              if (isLocked)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: lockedByMe ? AppColors.success : AppColors.warning,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.surface, width: 2),
                    ),
                    child: Icon(
                      Icons.lock,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  customerName,
                  style: AppTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isLocked)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: lockedByMe 
                        ? AppColors.success.withValues(alpha: 0.1)
                        : AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    lockedByMe ? 'Assigned to you' : 'Locked by ${chatRoom.lockedByCsrName}',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: lockedByMe ? AppColors.success : AppColors.warning,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Chat type indicator
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDedicatedSupport 
                        ? AppColors.primary.withValues(alpha: 0.1)
                        : AppColors.secondary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isDedicatedSupport 
                        ? (chatRoom.orderId != null 
                            ? 'Order #${chatRoom.orderId!.substring(0, 8).toUpperCase()}'
                            : 'Support Request')
                        : 'Buyer/Seller Chat${csrHasJoined ? '' : ' • New'}',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: isDedicatedSupport ? AppColors.primary : AppColors.secondary,
                      fontWeight: FontWeight.w500,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
              // Product info for buyer/seller chats
              if (!isDedicatedSupport && chatRoom.productName != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    chatRoom.productName!,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.onSurface.withValues(alpha: 0.6),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              // Last message preview
              if (lastMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    lastMessage.message,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.onSurface.withValues(alpha: 0.7),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatTimestamp(chatRoom.lastActivity),
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.onSurface.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 4),
              Icon(
                isDedicatedSupport ? Icons.support_agent : Icons.people,
                size: 16,
                color: AppColors.primary,
              ),
            ],
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ChatDetailPage(
                  chatRoomId: chatRoom.id,
                  otherUserName: customerName,
                  otherUserId: isDedicatedSupport ? chatRoom.user1Id : chatRoom.user1Id,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // Seller view: Show individual product inquiries grouped by buyer
  Widget _buildSellerChatList(List<ChatRoom> chatRooms, String currentUserId) {
    // Group chat rooms by buyer (other user)
    final Map<String, List<ChatRoom>> groupedByBuyer = {};

    for (final chatRoom in chatRooms) {
      final buyerId = chatRoom.getOtherUserId(currentUserId);
      if (!groupedByBuyer.containsKey(buyerId)) {
        groupedByBuyer[buyerId] = [];
      }
      groupedByBuyer[buyerId]!.add(chatRoom);
    }

    // Sort groups by most recent activity
    final sortedBuyers = groupedByBuyer.entries.toList()
      ..sort((a, b) {
        final aLatest = a.value
            .map((r) => r.lastActivity)
            .reduce((a, b) => a.isAfter(b) ? a : b);
        final bLatest = b.value
            .map((r) => r.lastActivity)
            .reduce((a, b) => a.isAfter(b) ? a : b);
        return bLatest.compareTo(aLatest);
      });

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: sortedBuyers.length,
      itemBuilder: (context, index) {
        final entry = sortedBuyers[index];
        final buyerChats = entry.value;

        // Sort buyer's chats by last activity
        buyerChats.sort((a, b) => b.lastActivity.compareTo(a.lastActivity));

        if (buyerChats.length == 1) {
          // Single chat with this buyer
          return _buildSellerChatRoomItem(buyerChats.first, currentUserId);
        } else {
          // Multiple product chats with same buyer - show as expandable group
          return _buildSellerGroupedChatItem(buyerChats, currentUserId);
        }
      },
    );
  }

  // Buyer view: Show individual product inquiries grouped by seller (same look as seller view)
  Widget _buildBuyerChatList(List<ChatRoom> chatRooms, String currentUserId) {
    // Group chat rooms by seller
    final Map<String, List<ChatRoom>> groupedBySeller = {};

    for (final chatRoom in chatRooms) {
      final sellerId =
          chatRoom.sellerId ?? chatRoom.getOtherUserId(currentUserId);
      if (!groupedBySeller.containsKey(sellerId)) {
        groupedBySeller[sellerId] = [];
      }
      groupedBySeller[sellerId]!.add(chatRoom);
    }

    // Sort groups by most recent activity
    final sortedSellers = groupedBySeller.entries.toList()
      ..sort((a, b) {
        final aLatest = a.value
            .map((r) => r.lastActivity)
            .reduce((a, b) => a.isAfter(b) ? a : b);
        final bLatest = b.value
            .map((r) => r.lastActivity)
            .reduce((a, b) => a.isAfter(b) ? a : b);
        return bLatest.compareTo(aLatest);
      });

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: sortedSellers.length,
      itemBuilder: (context, index) {
        final entry = sortedSellers[index];
        final sellerChats = entry.value;

        // Sort seller's chats by last activity
        sellerChats.sort((a, b) => b.lastActivity.compareTo(a.lastActivity));

        if (sellerChats.length == 1) {
          // Single chat with this seller - show with product info
          return _buildBuyerChatRoomItem(sellerChats.first, currentUserId);
        } else {
          // Multiple product chats with same seller - show as expandable group
          return _buildBuyerGroupedChatItem(sellerChats, currentUserId);
        }
      },
    );
  }

  // Seller view: Single chat room item showing product and buyer info
  Widget _buildSellerChatRoomItem(ChatRoom chatRoom, String currentUserId) {
    final buyerName = chatRoom.getOtherUserName(currentUserId);
    final buyerAvatar = chatRoom.getOtherUserAvatar(currentUserId);
    final lastMessage = chatRoom.lastMessage;
    final productName = chatRoom.productName;
    final productImage = chatRoom.productImage;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.onSurface.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _navigateToChatDetail(chatRoom, currentUserId),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Show product image if available, otherwise buyer avatar
                _buildChatAvatar(
                  imageUrl: productImage ?? buyerAvatar,
                  fallbackIcon: Icons.inventory_2,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Product name as main title
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              productName ?? 'General Inquiry',
                              style: AppTextStyles.bodyLarge.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppColors.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (lastMessage != null)
                            Text(
                              _formatTimestamp(lastMessage.timestamp),
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.onSurface.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                            ),
                        ],
                      ),
                      // Buyer name as subtitle
                      const SizedBox(height: 2),
                      Text(
                        'From: $buyerName',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // Last message
                      if (lastMessage != null) ...[
                        const SizedBox(height: 4),
                        _buildLastMessageRow(
                          lastMessage,
                          chatRoom.unreadCount,
                          currentUserId,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Seller view: Grouped chat item for multiple products from same buyer
  Widget _buildSellerGroupedChatItem(
    List<ChatRoom> chatRooms,
    String currentUserId,
  ) {
    final firstChat = chatRooms.first;
    final buyerName = firstChat.getOtherUserName(currentUserId);
    final buyerAvatar = firstChat.getOtherUserAvatar(currentUserId);
    final totalUnread = chatRooms.fold<int>(
      0,
      (sum, room) => sum + room.unreadCount,
    );
    final latestActivity = chatRooms
        .map((r) => r.lastActivity)
        .reduce((a, b) => a.isAfter(b) ? a : b);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.onSurface.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          leading: _buildChatAvatar(
            imageUrl: buyerAvatar,
            fallbackIcon: Icons.person,
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  buyerName,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _formatTimestamp(latestActivity),
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          subtitle: Row(
            children: [
              Icon(Icons.inventory_2, size: 14, color: AppColors.primary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${chatRooms.length} product inquiries',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (totalUnread > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    totalUnread.toString(),
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          children: chatRooms.map((room) {
            return _buildProductChatSubItem(room, currentUserId);
          }).toList(),
        ),
      ),
    );
  }

  // Sub-item for individual product in grouped seller view
  Widget _buildProductChatSubItem(ChatRoom chatRoom, String currentUserId) {
    final productName = chatRoom.productName;
    final productImage = chatRoom.productImage;
    final lastMessage = chatRoom.lastMessage;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _navigateToChatDetail(chatRoom, currentUserId),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              // Product image
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: productImage != null && productImage.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: productImage,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          width: 40,
                          height: 40,
                          color: AppColors.primary.withValues(alpha: 0.1),
                          child: Icon(
                            Icons.inventory_2,
                            size: 20,
                            color: AppColors.primary,
                          ),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          width: 40,
                          height: 40,
                          color: AppColors.primary.withValues(alpha: 0.1),
                          child: Icon(
                            Icons.inventory_2,
                            size: 20,
                            color: AppColors.primary,
                          ),
                        ),
                      )
                    : Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.inventory_2,
                          size: 20,
                          color: AppColors.primary,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      productName ?? 'General Inquiry',
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w500,
                        color: AppColors.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (lastMessage != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        lastMessage.message,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.onSurface.withValues(alpha: 0.6),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (chatRoom.unreadCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    chatRoom.unreadCount.toString(),
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Buyer view: Single chat room item showing shop and product info
  Widget _buildBuyerChatRoomItem(ChatRoom chatRoom, String currentUserId) {
    final shopName = chatRoom.getDisplayName(currentUserId);
    final shopAvatar = chatRoom.getOtherUserAvatar(currentUserId);
    final lastMessage = chatRoom.lastMessage;
    final productName = chatRoom.productName;
    final productImage = chatRoom.productImage;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.onSurface.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _navigateToChatDetail(chatRoom, currentUserId),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Show product image if available, otherwise shop avatar
                _buildChatAvatar(
                  imageUrl: productImage ?? shopAvatar,
                  fallbackIcon: Icons.inventory_2,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Product name as main title
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              productName ?? 'General Inquiry',
                              style: AppTextStyles.bodyLarge.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppColors.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (lastMessage != null)
                            Text(
                              _formatTimestamp(lastMessage.timestamp),
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.onSurface.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                            ),
                        ],
                      ),
                      // Shop name as subtitle
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.store, size: 12, color: AppColors.primary),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              shopName,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      // Last message
                      if (lastMessage != null) ...[
                        const SizedBox(height: 4),
                        _buildLastMessageRow(
                          lastMessage,
                          chatRoom.unreadCount,
                          currentUserId,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Buyer view: Grouped chat item for multiple products from same seller
  Widget _buildBuyerGroupedChatItem(
    List<ChatRoom> chatRooms,
    String currentUserId,
  ) {
    final firstChat = chatRooms.first;
    final shopName = firstChat.getDisplayName(currentUserId);
    final shopAvatar = firstChat.getOtherUserAvatar(currentUserId);
    final totalUnread = chatRooms.fold<int>(
      0,
      (sum, room) => sum + room.unreadCount,
    );
    final latestActivity = chatRooms
        .map((r) => r.lastActivity)
        .reduce((a, b) => a.isAfter(b) ? a : b);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.onSurface.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          leading: _buildChatAvatar(
            imageUrl: shopAvatar,
            fallbackIcon: Icons.store,
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  shopName,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _formatTimestamp(latestActivity),
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          subtitle: Row(
            children: [
              Icon(Icons.inventory_2, size: 14, color: AppColors.primary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${chatRooms.length} product inquiries',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (totalUnread > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    totalUnread.toString(),
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          children: chatRooms.map((room) {
            return _buildProductChatSubItem(room, currentUserId);
          }).toList(),
        ),
      ),
    );
  }

  // Helper: Build chat avatar
  Widget _buildChatAvatar({String? imageUrl, required IconData fallbackIcon}) {
    return CircleAvatar(
      radius: 28,
      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
      backgroundImage: imageUrl != null && imageUrl.isNotEmpty
          ? CachedNetworkImageProvider(imageUrl)
          : null,
      child: imageUrl == null || imageUrl.isEmpty
          ? Icon(fallbackIcon, size: 32, color: AppColors.primary)
          : null,
    );
  }

  // Helper: Build last message row
  Widget _buildLastMessageRow(
    ChatMessage lastMessage,
    int unreadCount,
    String currentUserId,
  ) {
    return Row(
      children: [
        if (lastMessage.senderId == currentUserId)
          Icon(
            Icons.reply,
            size: 14,
            color: AppColors.onSurface.withValues(alpha: 0.6),
          ),
        if (lastMessage.senderId == currentUserId) const SizedBox(width: 4),
        Expanded(
          child: Text(
            lastMessage.productId != null
                ? '📦 ${lastMessage.message}'
                : lastMessage.message,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.onSurface.withValues(alpha: 0.7),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (unreadCount > 0 && lastMessage.senderId != currentUserId)
          Container(
            margin: const EdgeInsets.only(left: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              unreadCount.toString(),
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.onPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }

  // Helper: Navigate to chat detail
  void _navigateToChatDetail(ChatRoom chatRoom, String currentUserId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatDetailPage(
          chatRoomId: chatRoom.id,
          otherUserId: chatRoom.getOtherUserId(currentUserId),
          otherUserName: chatRoom.getDisplayName(currentUserId),
          otherUserShopName: chatRoom.getDisplaySubtitle(currentUserId),
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d';
    } else {
      return DateFormat('MMM d').format(timestamp);
    }
  }
}
