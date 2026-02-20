import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ChatPage extends StatefulWidget {
  final String? receiverUserId;
  final String? receiverName;
  final String? groupId;
  final String chatName;
  final bool isGroup;

  const ChatPage({
    Key? key,
    this.receiverUserId,
    this.receiverName,
    this.groupId,
    required this.chatName,
    required this.isGroup,
  }) : super(key: key);

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _messageController = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  final _picker = ImagePicker();

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  bool _isUploading = false;
  bool _isGroupMember = false; // Track membership status
  bool _isCheckingMembership = true;

  @override
  void initState() {
    super.initState();
    if (widget.isGroup) {
      _checkGroupMembership();
    }
  }

  Future<void> _checkGroupMembership() async {
    if (!widget.isGroup || widget.groupId == null) return;
    
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    try {
      final groupDoc = await _firestore
          .collection('groups')
          .doc(widget.groupId)
          .get();

      if (groupDoc.exists) {
        final data = groupDoc.data() as Map<String, dynamic>;
        final members = List<String>.from(data['members'] ?? []);
        
        setState(() {
          _isGroupMember = members.contains(currentUser.uid);
          _isCheckingMembership = false;
        });
      } else {
        setState(() {
          _isGroupMember = false;
          _isCheckingMembership = false;
        });
      }
    } catch (e) {
      print('Error checking group membership: $e');
      setState(() {
        _isGroupMember = false;
        _isCheckingMembership = false;
      });
    }
  }

  Future<String?> _getUserName(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        return userData['name'] ?? userData['displayName'] ?? 'Unknown User';
      }
      return 'Unknown User';
    } catch (e) {
      print('Error getting user name: $e');
      return 'Unknown User';
    }
  }

  Future<void> _sendImage() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    if (widget.isGroup && !_isGroupMember) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Anda bukan anggota grup ini')),
      );
      return;
    }

    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70, // Compress image
    );
    
    if (image == null) {
      print('No image selected.');
      return;
    }

    print('Image path: ${image.path}');
    setState(() => _isUploading = true);

    try {
      final fileName = 'chat_images/${DateTime.now().millisecondsSinceEpoch}_${currentUser.uid}.jpg';
      final ref = _storage.ref().child(fileName);
      final uploadTask = ref.putFile(File(image.path));
      
      // Show upload progress
      uploadTask.snapshotEvents.listen((snapshot) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        print('Upload progress: ${(progress * 100).toStringAsFixed(2)}%');
      });
      
      final snapshot = await uploadTask;
      final imageUrl = await snapshot.ref.getDownloadURL();

      await _sendMessage(imageUrl: imageUrl);
    } catch (e) {
      print('Error uploading image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengunggah gambar: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _sendMessage({String? message, String? imageUrl}) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null || ((message?.isEmpty ?? true) && imageUrl == null)) return;

    if (widget.isGroup && !_isGroupMember) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Anda bukan anggota grup ini')),
      );
      return;
    }

    final senderId = currentUser.uid;
    
    // Get sender name
    String senderName = currentUser.displayName ?? 'Unknown User';
    try {
      final userDoc = await _firestore.collection('users').doc(senderId).get();
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        senderName = userData['name'] ?? userData['displayName'] ?? senderName;
      }
    } catch (e) {
      print('Error getting sender name: $e');
    }

    // Choose correct collection based on chat type
    final docRef = widget.isGroup
        ? _firestore.collection('groups').doc(widget.groupId).collection('messages') // Fixed: was 'group'
        : _firestore.collection('chats')
            .doc(_getChatRoomId(senderId, widget.receiverUserId!))
            .collection('messages');

    try {
      await docRef.add({
        'senderId': senderId,
        'senderName': senderName, // Add sender name for group chats
        'receiverId': widget.isGroup ? null : widget.receiverUserId,
        'text': message, // Changed from 'message' to 'text' for consistency
        'imageUrl': imageUrl,
        'timestamp': FieldValue.serverTimestamp(),
        'type': imageUrl != null ? 'image' : 'text',
        'isRead': false,
      });

      // Update group's last activity if it's a group chat
      if (widget.isGroup) {
        await _firestore.collection('groups').doc(widget.groupId).update({
          'lastActivity': FieldValue.serverTimestamp(),
          'lastMessage': message ?? '📷 Photo',
          'lastMessageBy': senderId,
        });
      }

      _messageController.clear();
      _focusNode.unfocus();
      
      // Scroll to bottom
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      print('Error sending message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengirim pesan: ${e.toString()}')),
        );
      }
    }
  }

  String _getChatRoomId(String uid1, String uid2) {
    return uid1.hashCode <= uid2.hashCode ? '${uid1}_$uid2' : '${uid2}_$uid1'; // Fixed underscore
  }

  @override
  void dispose() {
    _messageController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = _auth.currentUser;

    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chat')),
        body: const Center(child: Text('Anda belum login')),
      );
    }

    if (widget.isGroup && (widget.groupId == null || widget.groupId!.isEmpty)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chat')),
        body: const Center(child: Text('Group ID tidak ditemukan')),
      );
    }

    if (!widget.isGroup && (widget.receiverUserId == null || widget.receiverUserId!.isEmpty)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chat')),
        body: const Center(child: Text('User tujuan tidak ditemukan')),
      );
    }

    // Show loading while checking membership
    if (widget.isGroup && _isCheckingMembership) {
      return Scaffold(
        backgroundColor: const Color(0xFFFFF0F5),
        appBar: AppBar(
          backgroundColor: const Color(0xFFC2185B),
          foregroundColor: Colors.white,
          title: Text(widget.chatName),
          centerTitle: true,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Show error if not a group member
    if (widget.isGroup && !_isGroupMember) {
      return Scaffold(
        backgroundColor: const Color(0xFFFFF0F5),
        appBar: AppBar(
          backgroundColor: const Color(0xFFC2185B),
          foregroundColor: Colors.white,
          title: Text(widget.chatName),
          centerTitle: true,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.block, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Anda bukan anggota grup ini',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Hubungi admin grup untuk bergabung',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    final chatRoomId = widget.isGroup
        ? widget.groupId!
        : _getChatRoomId(currentUser.uid, widget.receiverUserId!);

    final msgCollection = widget.isGroup
        ? _firestore.collection('groups').doc(chatRoomId).collection('messages')
        : _firestore.collection('chats').doc(chatRoomId).collection('messages');

    return Scaffold(
      backgroundColor: const Color(0xFFFFF0F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFC2185B),
        foregroundColor: Colors.white,
        title: Text(widget.chatName),
        centerTitle: true,
        actions: widget.isGroup ? [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              // TODO: Navigate to group info page
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Info grup akan segera tersedia')),
              );
            },
          ),
        ] : null,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: msgCollection.orderBy('timestamp', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  print('Stream error: ${snapshot.error}');
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error, size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        Text('Terjadi kesalahan: ${snapshot.error}'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => setState(() {}),
                          child: const Text('Coba Lagi'),
                        ),
                      ],
                    ),
                  );
                }
                
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          widget.isGroup ? Icons.group : Icons.chat,
                          size: 64,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.isGroup 
                              ? 'Belum ada pesan di grup ini'
                              : 'Mulai percakapan dengan mengirim pesan',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final messages = snapshot.data!.docs;

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index].data() as Map<String, dynamic>;
                    final isMe = msg['senderId'] == currentUser.uid;
                    final isSystem = msg['senderId'] == 'system';

                    // Handle system messages
                    if (isSystem) {
                      return Center(
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            msg['text'] ?? msg['message'] ?? '',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 12),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.75,
                        ),
                        child: Column(
                          crossAxisAlignment: isMe 
                              ? CrossAxisAlignment.end 
                              : CrossAxisAlignment.start,
                          children: [
                            // Show sender name for group chats (except for own messages)
                            if (widget.isGroup && !isMe && msg['senderName'] != null)
                              Padding(
                                padding: const EdgeInsets.only(left: 12, bottom: 2),
                                child: Text(
                                  msg['senderName'],
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isMe ? const Color(0xFFC2185B) : Colors.white,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(12),
                                  topRight: const Radius.circular(12),
                                  bottomLeft: isMe ? const Radius.circular(12) : Radius.zero,
                                  bottomRight: isMe ? Radius.zero : const Radius.circular(12),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 2,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (msg['imageUrl'] != null)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8.0),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: CachedNetworkImage(
                                          imageUrl: msg['imageUrl'],
                                          width: 200,
                                          height: 200,
                                          fit: BoxFit.cover,
                                          placeholder: (context, url) => Container(
                                            width: 200,
                                            height: 200,
                                            color: Colors.grey[300],
                                            child: const Center(
                                              child: CircularProgressIndicator(),
                                            ),
                                          ),
                                          errorWidget: (context, url, error) => Container(
                                            width: 200,
                                            height: 200,
                                            color: Colors.grey[300],
                                            child: const Icon(Icons.error),
                                          ),
                                        ),
                                      ),
                                    ),
                                  if ((msg['text'] ?? msg['message']) != null && 
                                      (msg['text'] ?? msg['message']).toString().isNotEmpty)
                                    Text(
                                      msg['text'] ?? msg['message'] ?? '',
                                      style: TextStyle(
                                        color: isMe ? Colors.white : Colors.black87,
                                        fontSize: 15,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (_isUploading) 
            const LinearProgressIndicator(
              backgroundColor: Colors.grey,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFC2185B)),
            ),
          _chatInput(),
        ],
      ),
    );
  }

  Widget _chatInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black12, 
            blurRadius: 4, 
            offset: Offset(0, -2)
          )
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.image, color: Color(0xFFC2185B)),
              onPressed: _isUploading ? null : _sendImage,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _messageController,
                focusNode: _focusNode,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => !_isUploading 
                    ? _sendMessage(message: _messageController.text.trim()) 
                    : null,
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  hintText: 'Ketik pesan...',
                  filled: true,
                  fillColor: const Color(0xFFFFF0F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
                maxLines: null, // Allow multiline
                textCapitalization: TextCapitalization.sentences,
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: const Color(0xFFC2185B),
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white),
                onPressed: _isUploading
                    ? null
                    : () => _sendMessage(message: _messageController.text.trim()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}