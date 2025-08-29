import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/chat_service.dart';
import '../services/auth_service.dart';
import '../models/chat_message.dart';
import '../widgets/message_bubble.dart';
import 'login_screen.dart';

class UserChatScreen extends StatefulWidget {
  const UserChatScreen({Key? key}) : super(key: key);

  @override
  _UserChatScreenState createState() => _UserChatScreenState();
}

class _UserChatScreenState extends State<UserChatScreen> {
  final ChatService _chatService = ChatService();
  final AuthService _authService = AuthService();
  final TextEditingController _messageController = TextEditingController();
  String? _chatId;
  bool _isLoading = true;
  bool _sendingMessage = false;

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  Future<void> _initializeChat() async {
    final user = _authService.currentUser;
    if (user == null) {
      _navigateToLogin();
      return;
    }

    // Get or create chat for current user
    final chatId = await _chatService.getOrCreateChatForUser(user.uid);
    setState(() {
      _chatId = chatId;
      _isLoading = false;
    });

    // Send initial message if no messages exist
    _chatService.getChatMessages(chatId).first.then((messages) {
      if (messages.isEmpty) {
        _chatService.sendMessage(
          chatId: chatId,
          content: "Please state your problem, an admin will be here soon.",
          isAdmin: true,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || _chatId == null || _sendingMessage) {
      return;
    }

    final messageContent = _messageController.text.trim();
    _messageController.clear();

    setState(() {
      _sendingMessage = true;
    });

    try {
      await _chatService.sendMessage(
        chatId: _chatId!,
        content: messageContent,
        isAdmin: false,
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

  Future<void> _signOut() async {
    await _authService.signOut();
    _navigateToLogin();
  }

  void _navigateToLogin() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DentPal Support Chat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            onPressed: _signOut,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: _chatId == null
                      ? const Center(child: Text('Failed to load chat'))
                      : _buildChatMessages(),
                ),
                _buildMessageInput(),
              ],
            ),
    );
  }

  Widget _buildChatMessages() {
    return StreamBuilder<List<ChatMessage>>(
      stream: _chatService.getChatMessages(_chatId!),
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
