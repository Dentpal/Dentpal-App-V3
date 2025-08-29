import 'package:flutter/material.dart';
import '../models/chat_message.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;

  const MessageBubble({
    Key? key,
    required this.message,
    required this.isMe,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isMe ? Colors.blue[600] : Colors.grey[300],
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(0),
              bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMe && message.isAdmin)
                const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Admin',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.blue,
                    ),
                  ),
                ),
              Text(
                message.content,
                style: TextStyle(
                  color: isMe ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _formatTimestamp(message.timestamp),
                style: TextStyle(
                  fontSize: 10,
                  color: isMe ? Colors.white70 : Colors.black54,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(
      timestamp.year,
      timestamp.month,
      timestamp.day,
    );

    if (messageDate == today) {
      // Today, show only time
      return '${_formatTwoDigits(timestamp.hour)}:${_formatTwoDigits(timestamp.minute)}';
    } else {
      // Not today, show date and time
      return '${_formatTwoDigits(timestamp.day)}/${_formatTwoDigits(timestamp.month)} ${_formatTwoDigits(timestamp.hour)}:${_formatTwoDigits(timestamp.minute)}';
    }
  }

  String _formatTwoDigits(int number) {
    return number.toString().padLeft(2, '0');
  }
}
