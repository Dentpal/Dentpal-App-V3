import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dentpal/core/app_theme/app_text_styles.dart';
import 'package:dentpal/core/app_theme/ink_palette.dart';
import 'package:dentpal/core/app_theme/theme_utils.dart';
import 'package:dentpal/core/widgets/app_page_header.dart';
import 'package:dentpal/services/chat_service.dart';
import 'package:dentpal/product/services/user_service.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dentpal/product/pages/product_detail_page.dart';
import 'package:image_picker/image_picker.dart';

/// One conversation: its messages, and the composer under them.
///
/// Only [chatRoomId] is required. Callers that already know who is on the other
/// end pass it through so the header is right on the first frame; a link opened
/// cold — `/profile/chats/<id>` pasted or reloaded — carries nothing but the id,
/// and the rest is read off the chat room once it loads.
class ChatDetailPage extends StatefulWidget {
  final String chatRoomId;
  final String? otherUserId;
  final String? otherUserName;
  final String? otherUserShopName;

  const ChatDetailPage({
    super.key,
    required this.chatRoomId,
    this.otherUserId,
    this.otherUserName,
    this.otherUserShopName,
  });

  @override
  State<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends State<ChatDetailPage> {
  final ChatService _chatService = ChatService();
  final UserService _userService = UserService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  bool _isLoading = false;
  bool _isCurrentUserCsr = false;
  ChatRoom? _chatRoom;

  // Image upload state
  bool _isUploadingImage = false;
  double _uploadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    // Mark messages as read when opening chat
    _markMessagesAsRead();
    _loadChatRoomAndUserRole();
  }

  Future<void> _loadChatRoomAndUserRole() async {
    try {
      // Check if current user is CSR
      final isCsr = await _userService.isCurrentUserCustomerSupport();

      // Load chat room data
      final chatRoomRef = await _chatService.getChatRoom(widget.chatRoomId);

      if (mounted) {
        setState(() {
          _isCurrentUserCsr = isCsr;
          _chatRoom = chatRoomRef;
        });
        // Opened from a bare link, the recipient was unknown a moment ago, so
        // the first attempt in initState was a no-op. Marking twice is
        // harmless, and this is the only chance the deep-link path gets.
        _markMessagesAsRead();
      }
    } catch (e) {
      // Ignore errors
    }
  }

  // ── Who is on the other end ──────────────────────────────────────────────

  String? get _currentUserId => FirebaseAuth.instance.currentUser?.uid;

  /// The counterparty's id: what the caller handed over, or what the loaded
  /// chat room says. Null only in the window before the room arrives.
  String? get _otherUserId {
    final given = widget.otherUserId;
    if (given != null && given.isNotEmpty) return given;

    final room = _chatRoom;
    final me = _currentUserId;
    if (room == null || me == null) return null;
    return room.getOtherUserId(me);
  }

  /// What the header calls this conversation.
  String get _otherUserName {
    final given = widget.otherUserName;
    if (given != null && given.isNotEmpty) return given;

    final room = _chatRoom;
    final me = _currentUserId;
    if (room == null || me == null) return 'Conversation';
    return room.getDisplayName(me);
  }

  String? get _otherUserShopName {
    final given = widget.otherUserShopName;
    if (given != null && given.isNotEmpty) return given;

    final room = _chatRoom;
    final me = _currentUserId;
    if (room == null || me == null) return null;
    return room.getDisplaySubtitle(me);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _markMessagesAsRead() {
    final otherId = _otherUserId;
    // Retried from _loadChatRoomAndUserRole once the room identifies them.
    if (otherId == null) return;
    _chatService.markMessagesAsRead(widget.chatRoomId, otherId);
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _isLoading) return;

    // Check if this is a support chat or has support requested
    final isSupportChat = widget.chatRoomId.startsWith('support_');
    final hasSupportRequested = _chatRoom?.supportRequested == true;
    final sendsAsCsr =
        _isCurrentUserCsr && (isSupportChat || hasSupportRequested);

    // A link opened cold knows the room but not yet the recipient, and a
    // regular send is addressed to them. Better to say so than to post a
    // message into the void.
    final receiverId = _otherUserId;
    if (!sendsAsCsr && receiverId == null) {
      _showSnack(
        'Still opening this conversation — try again in a moment.',
        ink.amber,
        onTone: ink.onAmber,
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      if (sendsAsCsr) {
        // Get CSR name for the lock
        final currentUser = FirebaseAuth.instance.currentUser;
        String csrName = 'Support Agent';
        if (currentUser != null) {
          final userDoc = await _userService.getCurrentUserData();
          csrName =
              userDoc?['fullName'] ?? userDoc?['displayName'] ?? 'Support Agent';
        }

        // If CSR hasn't joined yet (for support requested chats), join first
        if (hasSupportRequested &&
            !_chatRoom!.hasCsrJoined &&
            currentUser != null) {
          await _chatService.joinChatAsSupport(
            chatRoomId: widget.chatRoomId,
            csrId: currentUser.uid,
            csrName: csrName,
          );
        }

        // Use the support message method which handles locking
        await _chatService.sendSupportMessage(
          chatRoomId: widget.chatRoomId,
          message: message,
          isFromCsr: true,
          csrId: currentUser?.uid,
          csrName: csrName,
        );
      } else {
        // Regular message or customer message in support chat
        await _chatService.sendMessage(
          chatRoomId: widget.chatRoomId,
          receiverId: receiverId!,
          message: message,
        );
      }

      _messageController.clear();

      // Scroll to bottom after sending message
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });

      // Reload chat room data to get updated lock status
      if (isSupportChat || hasSupportRequested) {
        _loadChatRoomAndUserRole();
      }
    } on ChatLockConflictException catch (e) {
      // Another CSR already locked this chat
      if (mounted) {
        _showSnack(e.message, ink.amber, seconds: 4);
        // Reload to get updated lock status
        _loadChatRoomAndUserRole();
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Failed to send message: $e', _danger);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pickAndSendImage() async {
    if (_isLoading) return;

    // Same as a text send: the picture is addressed to someone, and a link
    // opened cold does not know who until the room has loaded.
    final receiverId = _otherUserId;
    if (receiverId == null) {
      _showSnack(
        'Still opening this conversation — try again in a moment.',
        ink.amber,
        onTone: ink.onAmber,
      );
      return;
    }

    try {
      // Pick image from gallery
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      // Read image as bytes (works on both mobile and web)
      final imageBytes = await pickedFile.readAsBytes();

      // Show uploading state
      setState(() {
        _isUploadingImage = true;
        _uploadProgress = 0.0;
      });

      // Scroll to bottom to show the upload preview
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });

      // Upload image to Firebase Storage with progress
      final imageUrl = await _chatService.uploadChatImage(
        imageBytes: imageBytes,
        chatRoomId: widget.chatRoomId,
        fileName: pickedFile.name,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _uploadProgress = progress;
            });
          }
        },
      );

      // Hide uploading state before sending message
      setState(() {
        _isUploadingImage = false;
        _uploadProgress = 0.0;
      });

      // Send message with image
      await _chatService.sendMessage(
        chatRoomId: widget.chatRoomId,
        receiverId: receiverId,
        message: '📷 Image',
        imageUrl: imageUrl,
        messageType: 'image',
      );

      // Scroll to bottom after sending image
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });

      if (mounted) {
        _showSnack('Image sent', ink.emerald, seconds: 2);
      }
    } catch (e) {
      // Hide uploading state on error
      setState(() {
        _isUploadingImage = false;
        _uploadProgress = 0.0;
      });

      if (mounted) {
        _showSnack('Failed to send image: $e', _danger);
      }
    }
  }

  // ── Palette ──────────────────────────────────────────────────────────────

  InkPalette get ink => InkPalette.of(context);

  /// Destructive red. [InkPalette] reserves amber for urgency, so danger needs
  /// its own tone that still reads in both themes.
  Color get _danger =>
      ink.isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);

  Color get _muted => ink.text.withValues(alpha: 0.6);

  /// A conversation reads best in a narrower column than a browse grid, so the
  /// thread stops short of the page's full width — but it still centres inside
  /// the same frame every other buyer surface uses.
  static const double _threadMaxWidth = 720;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ink.bg,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _threadMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                Expanded(child: _buildMessages()),
                _buildMessageInput(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final shop = _otherUserShopName;

    return AppPageHeader(
      title: _otherUserName,
      subtitle: shop != null && shop.isNotEmpty ? shop : 'Conversation',
      subtitleColor: shop != null && shop.isNotEmpty ? ink.emerald : null,
      trailing: IconButton(
        icon: Icon(Icons.more_horiz, color: ink.text),
        onPressed: _showChatOptions,
        tooltip: 'Chat options',
      ),
    );
  }

  // ── Messages ─────────────────────────────────────────────────────────────

  static const EdgeInsets _listPadding = EdgeInsets.fromLTRB(
    AppLayout.gutter,
    4,
    AppLayout.gutter,
    16,
  );

  Widget _buildMessages() {
    return StreamBuilder<List<ChatMessage>>(
      stream: _chatService.getMessagesStream(widget.chatRoomId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildStateMessage(
            icon: Icons.cloud_off,
            tone: _danger,
            title: 'Couldn’t load messages',
            detail:
                'Check your connection — this thread updates on its own once '
                'it reconnects.',
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: ink.emerald),
          );
        }

        final messages = snapshot.data ?? const <ChatMessage>[];

        if (messages.isEmpty && !_isUploadingImage) {
          return _buildStateMessage(
            icon: Icons.chat_bubble_outline,
            tone: ink.emerald,
            title: 'Start the conversation',
            detail: 'Send a message to $_otherUserName.',
          );
        }

        // Auto-scroll to bottom when new messages arrive
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollToBottom();
          }
        });

        return ListView.builder(
          controller: _scrollController,
          padding: _listPadding,
          itemCount: messages.length + (_isUploadingImage ? 1 : 0),
          itemBuilder: (context, index) {
            // Show upload preview as the last item
            if (_isUploadingImage && index == messages.length) {
              return _buildUploadingImagePreview();
            }

            final message = messages[index];
            final isMe =
                message.senderId == FirebaseAuth.instance.currentUser?.uid;
            final showTimestamp =
                index == 0 ||
                messages[index - 1].timestamp
                        .difference(message.timestamp)
                        .inMinutes
                        .abs() >
                    5;

            return Column(
              children: [
                if (showTimestamp) _buildTimestampDivider(message.timestamp),
                _buildMessageBubble(message, isMe),
              ],
            );
          },
        );
      },
    );
  }

  /// A day or time marker between runs of messages.
  ///
  /// Two rules and a chip used to draw this; a single centred pill says the
  /// same thing without cutting the thread in half.
  Widget _buildTimestampDivider(DateTime timestamp) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: ink.surfaceHigh,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: ink.border),
          ),
          child: Text(
            _formatFullTimestamp(timestamp),
            style: AppTextStyles.bodySmall.copyWith(
              color: ink.text.withValues(alpha: 0.55),
              fontWeight: FontWeight.w600,
              fontSize: 11.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message, bool isMe) {
    final isImageOnly =
        message.messageType == 'image' && message.message == '📷 Image';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            _buildBubbleAvatar(message.senderAvatar),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.72,
              ),
              decoration: BoxDecoration(
                color: isMe ? ink.emerald : ink.surface,
                border: isMe ? null : Border.all(color: ink.border),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Product card if this is a product inquiry
                  if (message.productId != null && message.productName != null)
                    _buildProductCard(message, isMe),

                  // Image message
                  if (message.messageType == 'image' && message.imageUrl != null)
                    _buildImageMessage(message),

                  // Message text with its stamp (skipped for image-only sends,
                  // where the caption would just repeat the picture).
                  if (!isImageOnly)
                    Padding(
                      padding: EdgeInsets.all(
                        message.productId != null ? 8 : 12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            message.message,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: isMe ? ink.onEmerald : ink.text,
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          _buildStampRow(message, isMe),
                        ],
                      ),
                    ),

                  // Stamp for image-only messages
                  if (isImageOnly)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: _buildStampRow(message, isMe),
                    ),
                ],
              ),
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 8),
            _buildBubbleAvatar(null, isMe: true),
          ],
        ],
      ),
    );
  }

  Widget _buildBubbleAvatar(String? avatarUrl, {bool isMe = false}) {
    final hasImage = avatarUrl != null && avatarUrl.isNotEmpty;
    final tone = isMe ? ink.emeraldSoft : ink.emerald;

    return Container(
      width: 30,
      height: 30,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: tone.withValues(alpha: ink.isDark ? 0.16 : 0.11),
        shape: BoxShape.circle,
      ),
      child: hasImage
          ? CachedNetworkImage(
              imageUrl: avatarUrl,
              fit: BoxFit.cover,
              placeholder: (_, _) =>
                  Icon(Icons.person_outline, size: 16, color: tone),
              errorWidget: (_, _, _) =>
                  Icon(Icons.person_outline, size: 16, color: tone),
            )
          : Icon(Icons.person_outline, size: 16, color: tone),
    );
  }

  /// Time sent, plus delivery ticks on this account's own messages.
  ///
  /// The incoming side used to carry no stamp at all, so a reply could not be
  /// placed in time without scrolling up to the nearest divider.
  Widget _buildStampRow(ChatMessage message, bool isMe) {
    final tone = isMe
        ? ink.onEmerald.withValues(alpha: 0.75)
        : ink.text.withValues(alpha: 0.45);

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Text(
          _formatMessageTime(message.timestamp),
          style: AppTextStyles.bodySmall.copyWith(
            color: tone,
            fontWeight: FontWeight.w600,
            fontSize: 10.5,
          ),
        ),
        if (isMe) ...[
          const SizedBox(width: 4),
          _buildReadIndicator(message.isRead),
        ],
      ],
    );
  }

  Widget _buildImageMessage(ChatMessage message) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => _FullScreenImage(imageUrl: message.imageUrl!),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240, maxHeight: 240),
            child: CachedNetworkImage(
              imageUrl: message.imageUrl!,
              fit: BoxFit.cover,
              placeholder: (_, _) => Container(
                width: 200,
                height: 200,
                color: ink.surfaceHigh,
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: ink.emerald,
                  ),
                ),
              ),
              errorWidget: (_, _, _) => Container(
                width: 200,
                height: 200,
                color: ink.surfaceHigh,
                child: Icon(
                  Icons.broken_image_outlined,
                  color: ink.text.withValues(alpha: 0.3),
                  size: 40,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The picture being sent, in the place it will land, with its progress.
  Widget _buildUploadingImagePreview() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            decoration: BoxDecoration(
              color: ink.emerald,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.all(6),
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    color: ink.onEmerald.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 44,
                        height: 44,
                        child: CircularProgressIndicator(
                          value: _uploadProgress,
                          strokeWidth: 3,
                          backgroundColor: ink.onEmerald.withValues(alpha: 0.25),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            ink.onEmerald,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${(_uploadProgress * 100).toInt()}%',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: ink.onEmerald,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Uploading…',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: ink.onEmerald.withValues(alpha: 0.8),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        _formatMessageTime(DateTime.now()),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: ink.onEmerald.withValues(alpha: 0.75),
                          fontWeight: FontWeight.w600,
                          fontSize: 10.5,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.access_time,
                        size: 13,
                        color: ink.onEmerald.withValues(alpha: 0.7),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _buildBubbleAvatar(null, isMe: true),
        ],
      ),
    );
  }

  /// The product a message is about, inside the bubble that asked about it.
  Widget _buildProductCard(ChatMessage message, bool isMe) {
    // Inside an emerald bubble the card has to sit on the brand colour rather
    // than on the page ground, or it disappears into it.
    final cardColor = isMe
        ? ink.onEmerald.withValues(alpha: 0.14)
        : ink.surfaceHigh;
    final titleColor = isMe ? ink.onEmerald : ink.text;
    final hintColor = isMe
        ? ink.onEmerald.withValues(alpha: 0.8)
        : ink.emerald;

    return Padding(
      padding: const EdgeInsets.all(6),
      child: Material(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            if (message.productId != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      ProductDetailPage(productId: message.productId!),
                ),
              );
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Container(
                    width: 44,
                    height: 44,
                    color: isMe
                        ? ink.onEmerald.withValues(alpha: 0.15)
                        : ink.emerald.withValues(
                            alpha: ink.isDark ? 0.16 : 0.11,
                          ),
                    child:
                        message.productImage != null &&
                            message.productImage!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: message.productImage!,
                            fit: BoxFit.cover,
                            placeholder: (_, _) => Icon(
                              Icons.inventory_2_outlined,
                              size: 20,
                              color: hintColor,
                            ),
                            errorWidget: (_, _, _) => Icon(
                              Icons.broken_image_outlined,
                              size: 20,
                              color: hintColor,
                            ),
                          )
                        : Icon(
                            Icons.inventory_2_outlined,
                            size: 20,
                            color: hintColor,
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.productName ?? 'Product',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: titleColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tap to view product',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: hintColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: isMe
                      ? ink.onEmerald.withValues(alpha: 0.6)
                      : ink.text.withValues(alpha: 0.3),
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Composer ─────────────────────────────────────────────────────────────

  Widget _buildMessageInput() {
    final isSupportChat = widget.chatRoomId.startsWith('support_');
    final hasSupportRequested = _chatRoom?.supportRequested == true;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    // Check if CSR can message (chat not locked by another CSR)
    final isSupportRelated = isSupportChat || hasSupportRequested;
    final lockedByOther =
        isSupportRelated &&
        _isCurrentUserCsr &&
        _chatRoom != null &&
        _chatRoom!.isLocked &&
        _chatRoom!.lockedByCsrId != currentUserId;
    final lockedByMe =
        isSupportRelated &&
        _isCurrentUserCsr &&
        _chatRoom != null &&
        _chatRoom!.isLocked &&
        _chatRoom!.lockedByCsrId == currentUserId;
    final canCsrMessage = !lockedByOther;

    // Show lock notice instead of the composer when another agent holds it.
    if (lockedByOther) {
      return _buildComposerShell(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: ink.amber.withValues(alpha: ink.isDark ? 0.16 : 0.11),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ink.amber.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.lock_outline, color: ink.amber, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Locked by ${_chatRoom!.lockedByCsrName ?? 'another agent'}',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: ink.amber,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return _buildComposerShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Lock status banner for the CSR holding this chat.
          if (lockedByMe)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              decoration: BoxDecoration(
                color: ink.emerald.withValues(alpha: ink.isDark ? 0.16 : 0.11),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ink.emerald.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_outline, color: ink.emerald, size: 15),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You have this conversation locked',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: ink.emerald,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _unlockChat,
                    style: TextButton.styleFrom(
                      foregroundColor: ink.emerald,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: const Size(0, 32),
                    ),
                    child: Text(
                      'Unlock',
                      style: AppTextStyles.bodySmall.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildComposerIconButton(
                icon: Icons.image_outlined,
                tooltip: 'Send image',
                onPressed: (_isLoading || !canCsrMessage)
                    ? null
                    : _pickAndSendImage,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 46),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: ink.bg,
                    borderRadius: BorderRadius.circular(23),
                    border: Border.all(color: ink.border),
                  ),
                  child: Center(
                    child: TextField(
                      controller: _messageController,
                      enabled: canCsrMessage,
                      maxLines: 5,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: ink.text,
                        fontSize: 14,
                      ),
                      cursorColor: ink.emerald,
                      // The global inputDecorationTheme fills and outlines
                      // fields; this one draws its own shell, so all of that is
                      // switched off.
                      decoration: InputDecoration(
                        isDense: true,
                        filled: false,
                        fillColor: Colors.transparent,
                        contentPadding: const EdgeInsets.symmetric(vertical: 6),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        hintText: 'Type a message…',
                        hintStyle: AppTextStyles.bodyMedium.copyWith(
                          color: ink.text.withValues(alpha: 0.4),
                          fontSize: 14,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buildSendButton(canCsrMessage),
            ],
          ),
        ],
      ),
    );
  }

  /// The bar the composer sits in: a hairline above it rather than a shadow,
  /// matching how cards are separated everywhere else.
  Widget _buildComposerShell({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: ink.surface,
        border: Border(top: BorderSide(color: ink.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppLayout.gutter,
            10,
            AppLayout.gutter,
            10,
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildComposerIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    final enabled = onPressed != null;

    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 46,
        height: 46,
        child: Material(
          color: ink.emerald.withValues(
            alpha: enabled ? (ink.isDark ? 0.16 : 0.11) : 0.06,
          ),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Icon(
              icon,
              size: 20,
              color: ink.emerald.withValues(alpha: enabled ? 1 : 0.4),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSendButton(bool enabled) {
    final active = enabled && !_isLoading;

    return SizedBox(
      width: 46,
      height: 46,
      child: Material(
        color: active ? ink.emerald : ink.emerald.withValues(alpha: 0.4),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: active ? _sendMessage : null,
          child: _isLoading
              ? Padding(
                  padding: const EdgeInsets.all(13),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(ink.onEmerald),
                  ),
                )
              : Icon(Icons.send_rounded, color: ink.onEmerald, size: 19),
        ),
      ),
    );
  }

  // ── States ───────────────────────────────────────────────────────────────

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

  Future<void> _unlockChat() async {
    try {
      await _chatService.unlockSupportChat(chatRoomId: widget.chatRoomId);
      _loadChatRoomAndUserRole();
      if (mounted) {
        _showSnack('Chat unlocked', ink.emerald);
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Failed to unlock chat: $e', _danger);
      }
    }
  }

  void _showChatOptions() {
    final isSupportChat = widget.chatRoomId.startsWith('support_');
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    // Determine if "Contact Support" should be shown.
    // Hide if: it's already a support chat, support was requested, or a CSR has
    // joined.
    final canRequestSupport =
        !isSupportChat &&
        !_isCurrentUserCsr &&
        _chatRoom != null &&
        !_chatRoom!.supportRequested &&
        !_chatRoom!.hasCsrJoined;

    // Determine if CSR lock/unlock options should be shown.
    final showCsrOptions =
        _isCurrentUserCsr &&
        (_chatRoom?.isSupportChat == true ||
            _chatRoom?.supportRequested == true);
    final isLockedByMe = _chatRoom?.lockedByCsrId == currentUserId;

    final supportPending =
        !_isCurrentUserCsr &&
        _chatRoom != null &&
        (_chatRoom!.supportRequested || _chatRoom!.hasCsrJoined) &&
        !isSupportChat;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: ink.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: ink.border),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Grab handle
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 14),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: ink.text.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              if (canRequestSupport)
                _buildSheetRow(
                  icon: Icons.support_agent,
                  tone: ink.emerald,
                  label: 'Contact support',
                  detail: 'Ask a support agent to join this conversation',
                  onTap: () {
                    Navigator.pop(context);
                    _requestSupport();
                  },
                ),

              if (supportPending)
                _buildSheetRow(
                  icon: Icons.check_circle_outline,
                  tone: ink.emerald,
                  label: _chatRoom!.hasCsrJoined
                      ? 'Support agent active'
                      : 'Support requested',
                  detail: _chatRoom!.hasCsrJoined
                      ? '${_chatRoom!.csrName} is assisting you'
                      : 'A support agent will join shortly',
                ),

              if (showCsrOptions && isLockedByMe)
                _buildSheetRow(
                  icon: Icons.lock_open,
                  tone: ink.amber,
                  label: 'Unlock conversation',
                  detail: 'Allow other support agents to respond',
                  onTap: () {
                    Navigator.pop(context);
                    _unlockChat();
                  },
                ),

              _buildSheetRow(
                icon: Icons.delete_outline,
                tone: _danger,
                label: 'Delete chat',
                detail: 'Removes the entire conversation',
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteConfirmation();
                },
              ),

              const SizedBox(height: 14),
            ],
          ),
        ),
      ),
    );
  }

  /// One option in the sheet, in the same icon-tile shape the menus use.
  Widget _buildSheetRow({
    required IconData icon,
    required Color tone,
    required String label,
    required String detail,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppLayout.gutter,
            vertical: 12,
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: ink.isDark ? 0.16 : 0.11),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: tone, size: 19),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: tone,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: ink.text.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _requestSupport() async {
    try {
      await _chatService.requestSupportForChat(chatRoomId: widget.chatRoomId);
      _loadChatRoomAndUserRole();
      if (mounted) {
        _showSnack(
          'Support request sent. An agent will join shortly.',
          ink.emerald,
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Failed to request support: $e', _danger);
      }
    }
  }

  /// Confirms, then deletes — the two are kept apart so the delete never runs
  /// against the dialog's own context, which is gone the moment it is
  /// dismissed.
  Future<void> _showDeleteConfirmation() async {
    final confirmed = await showDialog<bool>(
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
          'This conversation will be permanently deleted.',
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

    if (confirmed != true || !mounted) return;

    // Captured before the await: this page is popped on success, so reaching
    // for its Navigator afterwards would be reaching through a dead context.
    final navigator = Navigator.of(context);
    try {
      await _chatService.deleteChatRoom(widget.chatRoomId);
      if (!mounted) return;
      navigator.pop(); // Back to the chats list
      _showSnack('Chat deleted', ink.emerald);
    } catch (e) {
      if (mounted) {
        _showSnack('Failed to delete chat: $e', _danger);
      }
    }
  }

  void _showSnack(
    String message,
    Color tone, {
    Color? onTone,
    int seconds = 3,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: onTone ?? Colors.white),
        ),
        backgroundColor: tone,
        duration: Duration(seconds: seconds),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildReadIndicator(bool isRead) {
    return Icon(
      isRead ? Icons.done_all : Icons.done,
      size: 13,
      color: ink.onEmerald.withValues(alpha: isRead ? 0.9 : 0.6),
    );
  }

  String _formatMessageTime(DateTime timestamp) {
    return DateFormat('h:mm a').format(timestamp);
  }

  String _formatFullTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays == 0) {
      return DateFormat('h:mm a').format(timestamp);
    } else if (difference.inDays == 1) {
      return 'Yesterday ${DateFormat('h:mm a').format(timestamp)}';
    } else if (difference.inDays < 7) {
      return DateFormat('EEEE h:mm a').format(timestamp);
    } else {
      return DateFormat('MMM d, y h:mm a').format(timestamp);
    }
  }
}

/// Full screen image viewer.
class _FullScreenImage extends StatelessWidget {
  final String imageUrl;

  const _FullScreenImage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.contain,
            placeholder: (_, _) => const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            errorWidget: (_, _, _) => const Center(
              child: Icon(Icons.broken_image, color: Colors.white, size: 64),
            ),
          ),
        ),
      ),
    );
  }
}
