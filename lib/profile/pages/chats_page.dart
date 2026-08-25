import 'package:dentpal/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dentpal/core/app_theme/app_text_styles.dart';
import 'package:dentpal/core/app_theme/ink_palette.dart';
import 'package:dentpal/core/app_theme/theme_utils.dart';
import 'package:dentpal/core/widgets/app_page_header.dart';
import 'package:dentpal/core/widgets/skeleton.dart';
import 'package:dentpal/services/chat_service.dart';
import 'package:dentpal/product/services/user_service.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Every conversation this account is part of.
///
/// Three audiences read the same list: a buyer sees their inquiries grouped by
/// shop, a seller sees theirs grouped by buyer, and a support agent sees the
/// support queue with its lock state. They share one card shape so the page
/// reads the same whoever opens it.
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

  // ── Palette ──────────────────────────────────────────────────────────────

  InkPalette get ink => InkPalette.of(context);

  /// Destructive red. [InkPalette] reserves amber for urgency, so danger needs
  /// its own tone that still reads in both themes.
  Color get _danger =>
      ink.isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);

  Color get _muted => ink.text.withValues(alpha: 0.6);

  static const EdgeInsets _listPadding = EdgeInsets.fromLTRB(
    AppLayout.gutter,
    4,
    AppLayout.gutter,
    24,
  );

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: ink.bg,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppLayout.maxContentWidth,
            ),
            child: currentUser == null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AppPageHeader(
                        title: 'Chats',
                        subtitle: 'Not signed in',
                      ),
                      Expanded(
                        child: _buildStateMessage(
                          icon: Icons.lock_outline,
                          tone: ink.emerald,
                          title: 'Sign in to view chats',
                          detail:
                              'Your conversations with sellers live here once '
                              'you are signed in.',
                        ),
                      ),
                    ],
                  )
                : StreamBuilder<List<ChatRoom>>(
                    // CSR users see support chats, others see regular chats.
                    stream: _isCurrentUserCsr
                        ? _chatService.getSupportChatRoomsStream()
                        : _chatService.getChatRoomsStream(),
                    builder: (context, snapshot) {
                      final rooms = snapshot.data ?? const <ChatRoom>[];
                      final unread = rooms.fold<int>(
                        0,
                        (sum, room) => sum + room.unreadCount,
                      );

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(rooms.length, unread),
                          Expanded(
                            child: _buildBody(snapshot, rooms, currentUser.uid),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────

  Widget _buildHeader(int roomCount, int unreadCount) {
    final String subtitle;
    if (_isLoadingUserRole) {
      subtitle = 'Loading your conversations…';
    } else if (roomCount == 0) {
      subtitle = 'No conversations yet';
    } else if (unreadCount > 0) {
      subtitle = '$unreadCount unread message${unreadCount == 1 ? '' : 's'}';
    } else {
      subtitle = '$roomCount conversation${roomCount == 1 ? '' : 's'}';
    }

    return AppPageHeader(
      title: 'Chats',
      subtitle: subtitle,
      subtitleColor: unreadCount > 0 ? ink.emerald : null,
      bottom: _buildSearchField(),
    );
  }

  Widget _buildSearchField() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: ink.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ink.border),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 20, color: ink.text.withValues(alpha: 0.5)),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (value) =>
                  setState(() => _searchQuery = value.toLowerCase()),
              textInputAction: TextInputAction.search,
              style: AppTextStyles.bodyMedium.copyWith(color: ink.text),
              cursorColor: ink.emerald,
              // The global inputDecorationTheme fills and outlines fields; this
              // one draws its own shell, so all of that is switched off.
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                fillColor: Colors.transparent,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: 'Search by shop, product or message…',
                hintStyle: AppTextStyles.bodyMedium.copyWith(
                  color: ink.text.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
          if (_searchQuery.isNotEmpty)
            GestureDetector(
              onTap: () {
                _searchController.clear();
                setState(() => _searchQuery = '');
              },
              child: Icon(
                Icons.close,
                size: 18,
                color: ink.text.withValues(alpha: 0.5),
              ),
            ),
        ],
      ),
    );
  }

  // ── Body ─────────────────────────────────────────────────────────────────

  Widget _buildBody(
    AsyncSnapshot<List<ChatRoom>> snapshot,
    List<ChatRoom> chatRooms,
    String currentUserId,
  ) {
    if (snapshot.hasError) {
      return _buildStateMessage(
        icon: Icons.cloud_off,
        tone: _danger,
        title: 'Couldn’t load chats',
        detail:
            'Check your connection — this list updates on its own once it '
            'reconnects.',
      );
    }

    if (_isLoadingUserRole ||
        snapshot.connectionState == ConnectionState.waiting) {
      return const _ChatsSkeleton(padding: _listPadding);
    }

    // Filter chat rooms based on search query.
    final filtered = chatRooms.where((chatRoom) {
      if (_searchQuery.isEmpty) return true;

      final displayName = chatRoom.getDisplayName(currentUserId).toLowerCase();
      final subtitle =
          chatRoom.getDisplaySubtitle(currentUserId)?.toLowerCase() ?? '';
      final productName = chatRoom.productName?.toLowerCase() ?? '';

      return displayName.contains(_searchQuery) ||
          subtitle.contains(_searchQuery) ||
          productName.contains(_searchQuery);
    }).toList();

    if (filtered.isEmpty) {
      return _buildStateMessage(
        icon: _searchQuery.isNotEmpty
            ? Icons.search_off
            : Icons.chat_bubble_outline,
        tone: ink.emerald,
        title: _searchQuery.isNotEmpty ? 'No chats found' : 'No chats yet',
        detail: _searchQuery.isNotEmpty
            ? 'Try a different search term, or clear the search to see every '
                  'conversation.'
            : 'Ask a seller about a product and the conversation will show up '
                  'here.',
      );
    }

    return _buildChatList(filtered, currentUserId);
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
      // For buyers: Group chats by seller (shop) with expandable product
      // inquiries — same experience as sellers but grouped the other way.
      return _buildBuyerChatList(chatRooms, currentUserId);
    }
  }

  // CSR view: Show all support chats with lock status
  Widget _buildCsrChatList(List<ChatRoom> chatRooms, String currentUserId) {
    return ListView.builder(
      padding: _listPadding,
      itemCount: chatRooms.length,
      itemBuilder: (context, index) =>
          _buildSupportChatTile(chatRooms[index], currentUserId),
    );
  }

  Widget _buildSupportChatTile(ChatRoom chatRoom, String currentUserId) {
    // For dedicated support chats, customer is user1.
    // For support requested chats, show both users (buyer and seller).
    final isDedicatedSupport = chatRoom.isSupportChat;
    final customerName = isDedicatedSupport
        ? chatRoom.user1Name
        : '${chatRoom.user1Name} & ${chatRoom.user2Name}';
    final lastMessage = chatRoom.lastMessage;
    final isLocked = chatRoom.isLocked;
    final lockedByMe = chatRoom.lockedByCsrId == currentUserId;
    final csrHasJoined = chatRoom.hasCsrJoined;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: Key(chatRoom.id),
        direction: DismissDirection.endToStart,
        background: _buildDismissBackground(),
        confirmDismiss: (direction) => _confirmDelete(),
        onDismissed: (direction) => _deleteChatRoom(chatRoom.id),
        child: _buildCard(
          onTap: () => Navigator.of(context).pushNamed(
            '/profile/chats/${chatRoom.id}',
            arguments: <String, dynamic>{
              'otherUserId': chatRoom.user1Id,
              'otherUserName': customerName,
            },
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildChatAvatar(
                imageUrl: chatRoom.user1Avatar,
                fallbackIcon: Icons.person_outline,
                // The lock is the one thing a support agent has to see before
                // opening the chat, so it rides on the avatar.
                badge: isLocked
                    ? _avatarBadge(
                        Icons.lock,
                        lockedByMe ? ink.emerald : ink.amber,
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTitleRow(
                      customerName,
                      _formatTimestamp(chatRoom.lastActivity),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _tag(
                          label: isDedicatedSupport
                              ? (chatRoom.orderId != null
                                    ? 'Order #${chatRoom.orderId!.substring(0, 8).toUpperCase()}'
                                    : 'Support request')
                              : 'Buyer/seller${csrHasJoined ? '' : ' • new'}',
                          icon: isDedicatedSupport
                              ? Icons.support_agent
                              : Icons.people_outline,
                          tone: isDedicatedSupport
                              ? ink.emerald
                              : ink.emeraldSoft,
                        ),
                        if (isLocked)
                          _tag(
                            label: lockedByMe
                                ? 'Assigned to you'
                                : 'Locked by ${chatRoom.lockedByCsrName ?? 'another agent'}',
                            icon: Icons.lock_outline,
                            tone: lockedByMe ? ink.emerald : ink.amber,
                          ),
                      ],
                    ),
                    if (!isDedicatedSupport && chatRoom.productName != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        chatRoom.productName!,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: ink.text.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (lastMessage != null) ...[
                      const SizedBox(height: 6),
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
    );
  }

  // Seller view: Show individual product inquiries grouped by buyer
  Widget _buildSellerChatList(List<ChatRoom> chatRooms, String currentUserId) {
    final sortedBuyers = _groupByMostRecent(
      chatRooms,
      (chatRoom) => chatRoom.getOtherUserId(currentUserId),
    );

    return ListView.builder(
      padding: _listPadding,
      itemCount: sortedBuyers.length,
      itemBuilder: (context, index) {
        final buyerChats = sortedBuyers[index];

        if (buyerChats.length == 1) {
          // Single chat with this buyer.
          return _buildSellerChatRoomItem(buyerChats.first, currentUserId);
        }
        // Multiple product chats with same buyer — show as expandable group.
        return _buildGroupedChatItem(
          chatRooms: buyerChats,
          currentUserId: currentUserId,
          title: buyerChats.first.getOtherUserName(currentUserId),
          avatarUrl: buyerChats.first.getOtherUserAvatar(currentUserId),
          fallbackIcon: Icons.person_outline,
        );
      },
    );
  }

  // Buyer view: Show individual product inquiries grouped by seller
  Widget _buildBuyerChatList(List<ChatRoom> chatRooms, String currentUserId) {
    final sortedSellers = _groupByMostRecent(
      chatRooms,
      (chatRoom) => chatRoom.sellerId ?? chatRoom.getOtherUserId(currentUserId),
    );

    return ListView.builder(
      padding: _listPadding,
      itemCount: sortedSellers.length,
      itemBuilder: (context, index) {
        final sellerChats = sortedSellers[index];

        if (sellerChats.length == 1) {
          // Single chat with this seller — show with product info.
          return _buildBuyerChatRoomItem(sellerChats.first, currentUserId);
        }
        // Multiple product chats with same seller — show as expandable group.
        return _buildGroupedChatItem(
          chatRooms: sellerChats,
          currentUserId: currentUserId,
          title: sellerChats.first.getDisplayName(currentUserId),
          avatarUrl: sellerChats.first.getOtherUserAvatar(currentUserId),
          fallbackIcon: Icons.storefront_outlined,
        );
      },
    );
  }

  /// Buckets [chatRooms] by [keyOf], newest conversation first both between
  /// buckets and inside each one.
  ///
  /// Buyer and seller lists differ only in what they group by, so the sorting
  /// lives here rather than being written out twice.
  List<List<ChatRoom>> _groupByMostRecent(
    List<ChatRoom> chatRooms,
    String Function(ChatRoom) keyOf,
  ) {
    final grouped = <String, List<ChatRoom>>{};
    for (final chatRoom in chatRooms) {
      grouped.putIfAbsent(keyOf(chatRoom), () => []).add(chatRoom);
    }

    final groups = grouped.values.toList();
    for (final group in groups) {
      group.sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
    }
    groups.sort(
      (a, b) => b.first.lastActivity.compareTo(a.first.lastActivity),
    );
    return groups;
  }

  // Seller view: Single chat room item showing product and buyer info
  Widget _buildSellerChatRoomItem(ChatRoom chatRoom, String currentUserId) {
    final buyerName = chatRoom.getOtherUserName(currentUserId);
    final lastMessage = chatRoom.lastMessage;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _buildCard(
        onTap: () => _navigateToChatDetail(chatRoom, currentUserId),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Show product image if available, otherwise buyer avatar.
            _buildChatAvatar(
              imageUrl:
                  chatRoom.productImage ??
                  chatRoom.getOtherUserAvatar(currentUserId),
              fallbackIcon: Icons.inventory_2_outlined,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTitleRow(
                    _getChatDisplayName(chatRoom),
                    lastMessage == null
                        ? null
                        : _formatTimestamp(lastMessage.timestamp),
                  ),
                  const SizedBox(height: 4),
                  _buildAttributionRow(Icons.person_outline, buyerName),
                  if (lastMessage != null) ...[
                    const SizedBox(height: 6),
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
    );
  }

  // Buyer view: Single chat room item showing shop and product info
  Widget _buildBuyerChatRoomItem(ChatRoom chatRoom, String currentUserId) {
    final shopName = chatRoom.getDisplayName(currentUserId);
    final lastMessage = chatRoom.lastMessage;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _buildCard(
        onTap: () => _navigateToChatDetail(chatRoom, currentUserId),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Show product image if available, otherwise shop avatar.
            _buildChatAvatar(
              imageUrl:
                  chatRoom.productImage ??
                  chatRoom.getOtherUserAvatar(currentUserId),
              fallbackIcon: Icons.inventory_2_outlined,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTitleRow(
                    _getChatDisplayName(chatRoom),
                    lastMessage == null
                        ? null
                        : _formatTimestamp(lastMessage.timestamp),
                  ),
                  const SizedBox(height: 4),
                  _buildAttributionRow(Icons.storefront_outlined, shopName),
                  if (lastMessage != null) ...[
                    const SizedBox(height: 6),
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
    );
  }

  /// Several inquiries with the same shop or buyer, collapsed into one card.
  ///
  /// Buyer and seller groups were two near-identical widgets; they differ only
  /// in what the heading names and which icon stands for the counterparty.
  Widget _buildGroupedChatItem({
    required List<ChatRoom> chatRooms,
    required String currentUserId,
    required String title,
    required String? avatarUrl,
    required IconData fallbackIcon,
  }) {
    final totalUnread = chatRooms.fold<int>(
      0,
      (sum, room) => sum + room.unreadCount,
    );
    final latestActivity = chatRooms.first.lastActivity;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: ink.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: ink.border),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(
            dividerColor: Colors.transparent,
            splashColor: ink.emerald.withValues(alpha: 0.08),
          ),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            iconColor: ink.text.withValues(alpha: 0.45),
            collapsedIconColor: ink.text.withValues(alpha: 0.35),
            leading: _buildChatAvatar(
              imageUrl: avatarUrl,
              fallbackIcon: fallbackIcon,
            ),
            title: _buildTitleRow(title, _formatTimestamp(latestActivity)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  _tag(
                    label: '${chatRooms.length} inquiries',
                    icon: Icons.inventory_2_outlined,
                    tone: ink.emerald,
                  ),
                  const Spacer(),
                  if (totalUnread > 0) _unreadBadge(totalUnread),
                ],
              ),
            ),
            children: [
              for (final room in chatRooms)
                _buildProductChatSubItem(room, currentUserId),
            ],
          ),
        ),
      ),
    );
  }

  // Sub-item for an individual product inside a grouped card
  Widget _buildProductChatSubItem(ChatRoom chatRoom, String currentUserId) {
    final productImage = chatRoom.productImage;
    final lastMessage = chatRoom.lastMessage;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: ink.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _navigateToChatDetail(chatRoom, currentUserId),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                _buildChatAvatar(
                  imageUrl: productImage,
                  fallbackIcon: Icons.inventory_2_outlined,
                  size: 38,
                  radius: 11,
                  iconSize: 19,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getChatDisplayName(chatRoom),
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: ink.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (lastMessage != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          lastMessage.message,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: ink.text.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (chatRoom.unreadCount > 0) ...[
                  const SizedBox(width: 8),
                  _unreadBadge(chatRoom.unreadCount),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Shared card furniture ────────────────────────────────────────────────

  /// The one card shape this page uses, so buyer, seller and support rows can
  /// never drift apart.
  Widget _buildCard({required VoidCallback onTap, required Widget child}) {
    return Material(
      color: ink.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: ink.border),
          ),
          child: Padding(padding: const EdgeInsets.all(14), child: child),
        ),
      ),
    );
  }

  /// Conversation name on the left, its stamp pinned right.
  Widget _buildTitleRow(String title, String? stamp) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            title,
            style: AppTextStyles.bodyMedium.copyWith(
              color: ink.text,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (stamp != null) ...[
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              stamp,
              style: AppTextStyles.bodySmall.copyWith(
                color: ink.text.withValues(alpha: 0.45),
                fontWeight: FontWeight.w600,
                fontSize: 11.5,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Who the conversation is with, under the title it belongs to.
  Widget _buildAttributionRow(IconData icon, String name) {
    return Row(
      children: [
        Icon(icon, size: 13, color: ink.emerald),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            name,
            style: AppTextStyles.bodySmall.copyWith(
              color: ink.emerald,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildChatAvatar({
    String? imageUrl,
    required IconData fallbackIcon,
    Widget? badge,
    double size = 48,
    double radius = 14,
    double iconSize = 22,
  }) {
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    final avatar = Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: ink.emerald.withValues(alpha: ink.isDark ? 0.16 : 0.11),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: hasImage
          ? CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              placeholder: (_, _) =>
                  Icon(fallbackIcon, size: iconSize, color: ink.emerald),
              errorWidget: (_, _, _) =>
                  Icon(fallbackIcon, size: iconSize, color: ink.emerald),
            )
          : Icon(fallbackIcon, size: iconSize, color: ink.emerald),
    );

    if (badge == null) return avatar;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(bottom: -2, right: -2, child: badge),
      ],
    );
  }

  Widget _avatarBadge(IconData icon, Color tone) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: tone,
        shape: BoxShape.circle,
        border: Border.all(color: ink.surface, width: 2),
      ),
      child: Icon(icon, size: 10, color: ink.onEmerald),
    );
  }

  /// Last thing said, with the unread count when it was not this account.
  Widget _buildLastMessageRow(
    ChatMessage lastMessage,
    int unreadCount,
    String currentUserId,
  ) {
    final fromMe = lastMessage.senderId == currentUserId;
    final unread = unreadCount > 0 && !fromMe;

    return Row(
      children: [
        if (fromMe) ...[
          Icon(Icons.reply, size: 13, color: ink.text.withValues(alpha: 0.4)),
          const SizedBox(width: 5),
        ],
        Expanded(
          child: Text(
            lastMessage.productId != null
                ? '📦 ${lastMessage.message}'
                : lastMessage.message,
            style: AppTextStyles.bodySmall.copyWith(
              color: ink.text.withValues(alpha: unread ? 0.75 : 0.5),
              fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
              fontSize: 12.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (unread) ...[
          const SizedBox(width: 8),
          _unreadBadge(unreadCount),
        ],
      ],
    );
  }

  Widget _unreadBadge(int count) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: ink.emerald,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: AppTextStyles.bodySmall.copyWith(
          color: ink.onEmerald,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }

  /// The page's one pill shape: a tone, an icon and a short label.
  Widget _tag({
    required String label,
    required IconData icon,
    required Color tone,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: ink.isDark ? 0.16 : 0.11),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tone.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: tone),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: tone,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDismissBackground() {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 22),
      decoration: BoxDecoration(
        color: _danger.withValues(alpha: ink.isDark ? 0.22 : 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _danger.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Icon(Icons.delete_outline, color: _danger, size: 20),
          const SizedBox(width: 8),
          Text(
            'Delete',
            style: AppTextStyles.bodySmall.copyWith(
              color: _danger,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStateMessage({
    required IconData icon,
    required Color tone,
    required String title,
    required String detail,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 40, 32, 60),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: tone.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 30, color: tone),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.titleMedium.copyWith(
                        color: ink.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      detail,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: _muted,
                        fontSize: 13.5,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<bool?> _confirmDelete() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ink.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.delete_outline, color: _danger),
            const SizedBox(width: 8),
            Text('Delete chat?', style: TextStyle(color: ink.text)),
          ],
        ),
        content: Text(
          'This conversation will be removed from your list.',
          style: AppTextStyles.bodyMedium.copyWith(color: _muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Keep', style: TextStyle(color: _muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _danger,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteChatRoom(String chatRoomId) async {
    try {
      await _chatService.deleteChatRoom(chatRoomId);
      if (mounted) {
        _showSnack('Chat deleted', ink.emerald);
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Failed to delete chat: $e', _danger);
      }
    }
  }

  void _showSnack(String message, Color tone) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: tone,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// Opens one conversation.
  ///
  /// Named rather than a direct push so the address bar reads
  /// `/profile/chats/<id>`; who is on the other end rides along in arguments,
  /// since the path alone would make the header wait for a read.
  void _navigateToChatDetail(ChatRoom chatRoom, String currentUserId) {
    Navigator.of(context).pushNamed(
      '/profile/chats/${chatRoom.id}',
      arguments: <String, dynamic>{
        'otherUserId': chatRoom.getOtherUserId(currentUserId),
        'otherUserName': chatRoom.getDisplayName(currentUserId),
        'otherUserShopName': chatRoom.getDisplaySubtitle(currentUserId),
      },
    );
  }

  // Helper: Get chat display name based on chat type
  String _getChatDisplayName(ChatRoom chatRoom) {
    // Order-related chats
    if (chatRoom.orderId != null && chatRoom.orderId!.isNotEmpty) {
      final shortOrderId = chatRoom.orderId!.length > 8
          ? chatRoom.orderId!.substring(0, 8).toUpperCase()
          : chatRoom.orderId!.toUpperCase();
      return 'Help with order — #$shortOrderId';
    }

    // Product inquiry chats
    if (chatRoom.productName != null && chatRoom.productName!.isNotEmpty) {
      return chatRoom.productName!;
    }

    return 'General chat';
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

/// Placeholder cards in the shape the real list settles into, so the page does
/// not jump when the stream arrives.
class _ChatsSkeleton extends StatelessWidget {
  const _ChatsSkeleton({this.padding = EdgeInsets.zero});

  final EdgeInsetsGeometry padding;

  /// Enough rows to fill a phone screen; the real list replaces them before a
  /// reader could count.
  static const int _itemCount = 6;

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);

    return SkeletonShimmer(
      child: ListView.builder(
        padding: padding,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _itemCount,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ink.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: ink.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkeletonBox(width: 48, height: 48, radius: 14),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      SkeletonLine(width: 160, height: 13),
                      SizedBox(height: 8),
                      SkeletonLine(width: 96, height: 11),
                      SizedBox(height: 8),
                      SkeletonLine(widthFactor: 0.8, height: 11),
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
}
