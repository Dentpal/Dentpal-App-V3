import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dentpal/core/app_theme/index.dart';
import 'package:dentpal/services/chat_service.dart';
import 'package:dentpal/product/services/user_service.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dentpal/product/pages/product_detail_page.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // Added for web detection
import 'package:image_picker/image_picker.dart';

class ChatDetailPage extends StatefulWidget {
  final String chatRoomId;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserShopName;

  const ChatDetailPage({
    super.key,
    required this.chatRoomId,
    required this.otherUserId,
    required this.otherUserName,
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
      }
    } catch (e) {
      // Ignore errors
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _markMessagesAsRead() {
    _chatService.markMessagesAsRead(widget.chatRoomId, widget.otherUserId);
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

    setState(() {
      _isLoading = true;
    });

    try {
      // Check if this is a support chat or has support requested
      final isSupportChat = widget.chatRoomId.startsWith('support_');
      final hasSupportRequested = _chatRoom?.supportRequested == true;
      
      if (_isCurrentUserCsr && (isSupportChat || hasSupportRequested)) {
        // Get CSR name for the lock
        final currentUser = FirebaseAuth.instance.currentUser;
        String csrName = 'Support Agent';
        if (currentUser != null) {
          final userDoc = await _userService.getCurrentUserData();
          csrName = userDoc?['fullName'] ?? userDoc?['displayName'] ?? 'Support Agent';
        }
        
        // If CSR hasn't joined yet (for support requested chats), join first
        if (hasSupportRequested && !_chatRoom!.hasCsrJoined && currentUser != null) {
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
          receiverId: widget.otherUserId,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: AppColors.warning,
            duration: const Duration(seconds: 4),
          ),
        );
        // Reload to get updated lock status
        _loadChatRoomAndUserRole();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
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
        receiverId: widget.otherUserId,
        message: '📷 Image',
        imageUrl: imageUrl,
        messageType: 'image',
      );

      // Scroll to bottom after sending image
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image sent successfully'),
            backgroundColor: AppColors.success,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // Hide uploading state on error
      setState(() {
        _isUploadingImage = false;
        _uploadProgress = 0.0;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send image: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.otherUserName,
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.onSurface,
              ),
            ),
            if (widget.otherUserShopName != null &&
                widget.otherUserShopName!.isNotEmpty)
              Text(
                widget.otherUserShopName!,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: AppColors.onSurface),
            onPressed: () {
              _showChatOptions();
            },
          ),
        ],
      ),
      // Responsive wrapper added (web-only centered layout when wide)
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWideWeb = kIsWeb && constraints.maxWidth > 800; // BREAKPOINT
          final content = Column(
            children: [
              // Messages list
              Expanded(
                child: StreamBuilder<List<ChatMessage>>(
                  stream: _chatService.getMessagesStream(widget.chatRoomId),
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
                              'Error loading messages',
                              style: AppTextStyles.titleMedium.copyWith(
                                color: AppColors.error,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    final messages = snapshot.data ?? [];

                    if (messages.isEmpty) {
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
                                Icons.chat_bubble_outline,
                                size: 64,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Start the conversation',
                              style: AppTextStyles.titleMedium.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.onSurface,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Send a message to ${widget.otherUserName}',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.onSurface.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
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
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length + (_isUploadingImage ? 1 : 0),
                      itemBuilder: (context, index) {
                        // Show upload preview as the last item
                        if (_isUploadingImage && index == messages.length) {
                          return _buildUploadingImagePreview();
                        }

                        final message = messages[index];
                        final isMe =
                            message.senderId ==
                            FirebaseAuth.instance.currentUser?.uid;
                        final showTimestamp =
                            index == 0 ||
                            messages[index - 1].timestamp
                                    .difference(message.timestamp)
                                    .inMinutes
                                    .abs() >
                                5;

                        return Column(
                          children: [
                            if (showTimestamp)
                              _buildTimestampDivider(message.timestamp),
                            _buildMessageBubble(message, isMe),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),

              // Message input
              _buildMessageInput(),
            ],
          );
          if (isWideWeb) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640), // MAX_WIDTH
                child: Material(color: Colors.transparent, child: content),
              ),
            );
          }
          return content; // mobile & narrow web full width
        },
      ),
    );
  }

  Widget _buildTimestampDivider(DateTime timestamp) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.onSurface.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _formatFullTimestamp(timestamp),
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message, bool isMe) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
              backgroundImage:
                  message.senderAvatar != null &&
                      message.senderAvatar!.isNotEmpty
                  ? CachedNetworkImageProvider(message.senderAvatar!)
                  : null,
              child:
                  message.senderAvatar == null || message.senderAvatar!.isEmpty
                  ? Icon(Icons.person, size: 20, color: AppColors.primary)
                  : null,
            ),
            const SizedBox(width: 8),
          ],

          Expanded(
            child: Align(
              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: IntrinsicWidth(
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                  ),
                  decoration: BoxDecoration(
                    color: isMe ? AppColors.primary : AppColors.surface,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: isMe
                          ? const Radius.circular(16)
                          : const Radius.circular(4),
                      bottomRight: isMe
                          ? const Radius.circular(4)
                          : const Radius.circular(16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.onSurface.withValues(alpha: 0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Product card if this is a product inquiry
                      if (message.productId != null &&
                          message.productName != null)
                        _buildProductCard(message),

                      // Image message
                      if (message.messageType == 'image' && message.imageUrl != null)
                        _buildImageMessage(message, isMe),

                      // Message text with read indicator (skip for image-only messages)
                      if (message.messageType != 'image' || message.message != '📷 Image')
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
                                  color: isMe
                                      ? AppColors.onPrimary
                                      : AppColors.onSurface,
                                  height: 1.4,
                                ),
                              ),
                              if (isMe) ...[
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text(
                                      _formatMessageTime(message.timestamp),
                                      style: AppTextStyles.bodySmall.copyWith(
                                        color: AppColors.onPrimary.withValues(
                                          alpha: 0.7,
                                        ),
                                        fontSize: 10,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    _buildReadIndicator(message.isRead),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),

                      // Time and read indicator for image-only messages
                      if (message.messageType == 'image' && message.message == '📷 Image' && isMe)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                _formatMessageTime(message.timestamp),
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.onPrimary.withValues(
                                    alpha: 0.7,
                                  ),
                                  fontSize: 10,
                                ),
                              ),
                              const SizedBox(width: 4),
                              _buildReadIndicator(message.isRead),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          if (isMe) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.secondary.withValues(alpha: 0.1),
              child: Icon(Icons.person, size: 20, color: AppColors.secondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildImageMessage(ChatMessage message, bool isMe) {
    return GestureDetector(
      onTap: () {
        // Open image in full screen
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => _FullScreenImage(imageUrl: message.imageUrl!),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.all(8),
        constraints: const BoxConstraints(
          maxWidth: 250,
          maxHeight: 250,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: message.imageUrl!,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(
              color: AppColors.onSurface.withValues(alpha: 0.1),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
            errorWidget: (context, url, error) => Container(
              color: AppColors.onSurface.withValues(alpha: 0.1),
              child: Icon(
                Icons.broken_image,
                color: AppColors.onSurface.withValues(alpha: 0.3),
                size: 48,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUploadingImagePreview() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Image preview container with fixed width
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(4),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.onSurface.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Image preview with loading overlay
                Container(
                  margin: const EdgeInsets.all(8),
                  width: 200,
                  height: 200,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Blurred preview
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 200,
                          height: 200,
                          color: AppColors.onPrimary.withValues(alpha: 0.2),
                          child: const Icon(
                            Icons.image,
                            size: 48,
                            color: AppColors.onPrimary,
                          ),
                        ),
                      ),
                      
                      // Loading overlay
                      Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Circular progress indicator
                            SizedBox(
                              width: 50,
                              height: 50,
                              child: CircularProgressIndicator(
                                value: _uploadProgress,
                                strokeWidth: 3,
                                backgroundColor: Colors.white.withValues(alpha: 0.3),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            // Progress percentage
                            Text(
                              '${(_uploadProgress * 100).toInt()}%',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Uploading...',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Timestamp
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        _formatMessageTime(DateTime.now()),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.onPrimary.withValues(alpha: 0.7),
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.access_time,
                        size: 14,
                        color: AppColors.onPrimary.withValues(alpha: 0.6),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(width: 8),
          
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.secondary.withValues(alpha: 0.1),
            child: Icon(Icons.person, size: 20, color: AppColors.secondary),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(ChatMessage message) {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.onSurface.withValues(alpha: 0.1)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
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
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Product image
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 50,
                    height: 50,
                    color: AppColors.onSurface.withValues(alpha: 0.1),
                    child:
                        message.productImage != null &&
                            message.productImage!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: message.productImage!,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: AppColors.onSurface.withValues(alpha: 0.1),
                              child: Icon(
                                Icons.image,
                                color: AppColors.onSurface.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: AppColors.onSurface.withValues(alpha: 0.1),
                              child: Icon(
                                Icons.broken_image,
                                color: AppColors.onSurface.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                            ),
                          )
                        : Icon(
                            Icons.shopping_bag,
                            color: AppColors.onSurface.withValues(alpha: 0.3),
                          ),
                  ),
                ),

                const SizedBox(width: 12),

                // Product info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.productName ?? 'Product',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurface,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tap to view product',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                Icon(
                  Icons.chevron_right,
                  color: AppColors.onSurface.withValues(alpha: 0.4),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    final isSupportChat = widget.chatRoomId.startsWith('support_');
    final hasSupportRequested = _chatRoom?.supportRequested == true;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    
    // Check if CSR can message (chat not locked by another CSR)
    final isSupportRelated = isSupportChat || hasSupportRequested;
    final canCsrMessage = !isSupportRelated || 
        !_isCurrentUserCsr ||
        _chatRoom == null ||
        !_chatRoom!.isLocked ||
        _chatRoom!.lockedByCsrId == currentUserId;
    
    // Show lock indicator for CSRs viewing support chats locked by another CSR
    if (isSupportRelated && _isCurrentUserCsr && _chatRoom != null && _chatRoom!.isLocked && _chatRoom!.lockedByCsrId != currentUserId) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          boxShadow: [
            BoxShadow(
              color: AppColors.onSurface.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.lock, color: AppColors.warning, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'This conversation is locked by ${_chatRoom!.lockedByCsrName ?? 'another agent'}',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.warning,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: AppColors.onSurface.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Show lock status banner for CSR who locked this chat
            if (isSupportRelated && _isCurrentUserCsr && _chatRoom != null && _chatRoom!.isLocked && _chatRoom!.lockedByCsrId == currentUserId)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock, color: AppColors.success, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You have this conversation locked',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.success,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _unlockChat,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.success,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        minimumSize: const Size(0, 32),
                      ),
                      child: const Text('Unlock'),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                // Image picker button
                IconButton(
                  icon: Icon(
                    Icons.image,
                    color: canCsrMessage
                        ? AppColors.primary
                        : AppColors.primary.withValues(alpha: 0.5),
                  ),
                  onPressed: (_isLoading || !canCsrMessage) ? null : _pickAndSendImage,
                  tooltip: 'Send image',
                ),

                const SizedBox(width: 4),

                Expanded(
                  child: TextField(
                    controller: _messageController,
                    enabled: canCsrMessage,
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.onSurface.withValues(alpha: 0.5),
                      ),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: AppColors.primary, width: 2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),

                const SizedBox(width: 12),

                GestureDetector(
                  onTap: (_isLoading || !canCsrMessage) ? null : _sendMessage,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: canCsrMessage
                          ? AppColors.primary
                          : AppColors.primary.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: _isLoading
                        ? Container(
                            padding: const EdgeInsets.all(12),
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.onPrimary,
                              ),
                            ),
                          )
                        : Icon(
                            Icons.send,
                            color: AppColors.onPrimary,
                            size: 20,
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _unlockChat() async {
    try {
      await _chatService.unlockSupportChat(chatRoomId: widget.chatRoomId);
      _loadChatRoomAndUserRole();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chat unlocked successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to unlock chat: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showChatOptions() {
    final isSupportChat = widget.chatRoomId.startsWith('support_');
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    
    // Determine if "Contact Support" should be shown
    // Hide if: it's already a support chat, support was requested, or CSR has joined
    final canRequestSupport = !isSupportChat && 
        !_isCurrentUserCsr && 
        _chatRoom != null &&
        !_chatRoom!.supportRequested && 
        !_chatRoom!.hasCsrJoined;
    
    // Determine if CSR lock/unlock options should be shown
    final showCsrOptions = _isCurrentUserCsr && 
        (_chatRoom?.isSupportChat == true || _chatRoom?.supportRequested == true);
    final isLockedByMe = _chatRoom?.lockedByCsrId == currentUserId;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.onSurface.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              const SizedBox(height: 24),

              // Contact Support option (for buyers/sellers)
              if (canRequestSupport)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.support_agent,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    'Contact Support',
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: AppColors.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    'Request a support agent to join this conversation',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _requestSupport();
                  },
                ),
              
              // Support already requested indicator (for buyers/sellers)
              if (!_isCurrentUserCsr && _chatRoom != null && 
                  (_chatRoom!.supportRequested || _chatRoom!.hasCsrJoined) && 
                  !isSupportChat)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.check_circle_outline,
                      color: AppColors.success,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    _chatRoom!.hasCsrJoined 
                        ? 'Support Agent Active' 
                        : 'Support Requested',
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    _chatRoom!.hasCsrJoined 
                        ? '${_chatRoom!.csrName} is assisting you'
                        : 'A support agent will join shortly',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              
              // CSR Lock/Unlock option
              if (showCsrOptions && isLockedByMe)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.lock_open,
                      color: AppColors.warning,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    'Unlock Conversation',
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: AppColors.warning,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    'Allow other support agents to respond',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _unlockChat();
                  },
                ),

              // Delete chat option
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.delete_outline,
                    color: AppColors.error,
                    size: 20,
                  ),
                ),
                title: Text(
                  'Delete Chat',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.error,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  'This will delete the entire conversation',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteConfirmation();
                },
              ),

              const SizedBox(height: 24),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Support request sent. A support agent will join shortly.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to request support: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.delete_outline,
                color: AppColors.error,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Delete Chat',
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete this conversation? This action cannot be undone.',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.onSurface.withValues(alpha: 0.8),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.onSurface.withValues(alpha: 0.6),
            ),
            child: Text('Cancel', style: AppTextStyles.buttonMedium),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              try {
                await _chatService.deleteChatRoom(widget.chatRoomId);
                if (mounted) {
                  Navigator.of(context).pop(); // Go back to chats list
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Chat deleted successfully'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to delete chat: ${e.toString()}'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.onPrimary,
              elevation: 0,
            ),
            child: Text('Delete', style: AppTextStyles.buttonMedium),
          ),
        ],
      ),
    );
  }

  Widget _buildReadIndicator(bool isRead) {
    if (isRead) {
      // Double check mark for read messages
      return Stack(
        children: [
          Icon(
            Icons.check,
            size: 14,
            color: AppColors.onPrimary.withValues(alpha: 0.8),
          ),
          Positioned(
            left: 4,
            child: Icon(
              Icons.check,
              size: 14,
              color: AppColors.onPrimary.withValues(alpha: 0.8),
            ),
          ),
        ],
      );
    } else {
      // Single check mark for sent but unread messages
      return Icon(
        Icons.check,
        size: 14,
        color: AppColors.onPrimary.withValues(alpha: 0.6),
      );
    }
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

// Full screen image viewer
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
            placeholder: (context, url) => const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            errorWidget: (context, url, error) => const Center(
              child: Icon(
                Icons.broken_image,
                color: Colors.white,
                size: 64,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
