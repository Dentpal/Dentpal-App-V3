import 'package:flutter/material.dart';
import '../services/chat_service.dart';
import '../services/auth_service.dart';
import '../models/chat_message.dart';
import '../widgets/message_bubble.dart';

class AdminChatScreen extends StatefulWidget {
  final String chatId;
  final String userId;
  final String userEmail;

  const AdminChatScreen({
    Key? key,
    required this.chatId,
    required this.userId,
    required this.userEmail,
  }) : super(key: key);

  @override
  _AdminChatScreenState createState() => _AdminChatScreenState();
}

class _AdminChatScreenState extends State<AdminChatScreen> {
  final ChatService _chatService = ChatService();
  final AuthService _authService = AuthService();
  final TextEditingController _messageController = TextEditingController();
  bool _sendingMessage = false;

  @override
  void initState() {
    super.initState();
    _joinChat();
  }

  Future<void> _joinChat() async {
    final currentUser = _authService.currentUser;
    if (currentUser == null) return;
    
    // Add admin to chat and send notification
    await _chatService.addAdminToChat(widget.chatId, currentUser.uid);
    
    // Mark messages as read
    await _chatService.markMessagesAsRead(widget.chatId, currentUser.uid);
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || _sendingMessage) {
      return;
    }

    final messageContent = _messageController.text.trim();
    _messageController.clear();

    setState(() {
      _sendingMessage = true;
    });

    try {
      await _chatService.sendMessage(
        chatId: widget.chatId,
        content: messageContent,
        isAdmin: true,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send message: ${e.toString()}')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _sendingMessage = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Chat with ${widget.userEmail}'),
      ),
      body: Column(
        children: [
          Expanded(
            child: _buildChatMessages(),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildChatMessages() {
    return StreamBuilder<List<ChatMessage>>(
      stream: _chatService.getChatMessages(widget.chatId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final messages = snapshot.data ?? [];
        
        if (messages.isEmpty) {
          return const Center(child: Text('No messages yet'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: messages.length,
          reverse: false,
          itemBuilder: (context, index) {
            final message = messages[index];
            final isMe = message.senderId == _authService.currentUser?.uid;
            final isSystem = message.senderId == 'system';
            
            if (isSystem) {
              return Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    message.content,
                    style: const TextStyle(
                      fontStyle: FontStyle.italic,
                      color: Colors.black87,
                    ),
                  ),
                ),
              );
            }
            
            return MessageBubble(
              message: message,
              isMe: isMe,
            );
          },
        );
      },
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.3),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(24)),
                ),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.blue,
            ),
            child: IconButton(
              icon: _sendingMessage
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.send, color: Colors.white),
              onPressed: _sendMessage,
            ),
          ),
        ],
      ),
    );
  }
}
