import 'package:flutter/material.dart';
import '../services/chat_service.dart';
import '../services/auth_service.dart';
import '../models/chat_user.dart';
import 'admin_chat_screen.dart';
import 'login_screen.dart';

class AdminChatListScreen extends StatefulWidget {
  const AdminChatListScreen({Key? key}) : super(key: key);

  @override
  _AdminChatListScreenState createState() => _AdminChatListScreenState();
}

class _AdminChatListScreenState extends State<AdminChatListScreen> {
  final ChatService _chatService = ChatService();
  final AuthService _authService = AuthService();
  
  @override
  void initState() {
    super.initState();
    _checkIfAdmin();
  }
  
  Future<void> _checkIfAdmin() async {
    final user = _authService.currentUser;
    if (user == null) {
      _navigateToLogin();
      return;
    }
    
    final isAdmin = await _authService.isAdmin(user.uid);
    if (!isAdmin && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Access denied. You are not an admin.')),
      );
      _navigateToLogin();
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

  void _navigateToChatWithUser(ChatUser user) async {
    final chatId = await _chatService.getOrCreateChatForUser(user.uid);
    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => AdminChatScreen(
            chatId: chatId,
            userId: user.uid,
            userEmail: user.email,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            onPressed: _signOut,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'User Conversations',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          Expanded(
            child: StreamBuilder<List<ChatUser>>(
              stream: _chatService.getUsersForAdmin(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                final users = snapshot.data ?? [];
                
                if (users.isEmpty) {
                  return const Center(child: Text('No users available'));
                }

                return ListView.builder(
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final user = users[index];
                    return _buildUserListItem(user);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildUserListItem(ChatUser user) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue.shade200,
          child: const Icon(Icons.person, color: Colors.white),
        ),
        title: Text(user.email),
        subtitle: user.lastMessage != null
            ? Text(
                user.lastMessage!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : const Text('No messages yet'),
        trailing: user.hasUnreadMessages
            ? Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: const Text(
                  '!',
                  style: TextStyle(color: Colors.white),
                ),
              )
            : null,
        onTap: () => _navigateToChatWithUser(user),
      ),
    );
  }
}
