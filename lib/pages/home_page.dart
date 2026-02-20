import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hay_chat/pages/login_page.dart';
import 'package:hay_chat/pages/chat_page.dart';
import 'package:hay_chat/pages/create_group_page.dart';
import 'package:hay_chat/pages/group_chat_page.dart';
import 'package:hay_chat/pages/group_list_page.dart'; // Tambahkan ini

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    if (_auth.currentUser == null) {
      _redirectToLogin();
    }
  }

  void _redirectToLogin() {
    Future.delayed(Duration.zero, () {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
        (route) => false,
      );
    });
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    _redirectToLogin();
  }

  void _navigateToGroupChat() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CreateGroupPage()),
    );
  }

  void _navigateToGroupList() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GroupListPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_auth.currentUser == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final currentUserId = _auth.currentUser!.uid;

    return Scaffold(
      backgroundColor: const Color(0xFFFFF0F5),
      appBar: AppBar(
        title: const Text(
          'Poping',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFFC2185B),
        actions: [
          IconButton(
            icon: const Icon(Icons.group, color: Colors.white),
            tooltip: "Lihat Grup Saya",
            onPressed: _navigateToGroupList,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: "Logout",
            onPressed: _signOut,
          ),
        ],
      ),
      body: _buildUsersList(currentUserId),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToGroupChat,
        backgroundColor: const Color(0xFFC2185B),
        child: const Icon(Icons.group_add),
        tooltip: "Buat Grup Baru",
      ),
    );
  }

  Widget _buildUsersList(String currentUserId) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('users').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.data == null || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('Tidak ada data pengguna'));
        }

        final users = snapshot.data!.docs;
        final filteredUsers = users.where((doc) => doc.id != currentUserId).toList();

        if (filteredUsers.isEmpty) {
          return const Center(child: Text('Belum ada pengguna lain yang terdaftar'));
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          itemCount: filteredUsers.length,
          itemBuilder: (context, index) {
            final doc = filteredUsers[index];
            final userId = doc.id;
            final data = doc.data() as Map<String, dynamic>;

            final userName = data['name'] as String? ?? 'User';
            final userEmail = data['email'] as String? ?? 'No Email';

            return Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              margin: const EdgeInsets.symmetric(vertical: 8),
              color: Colors.white,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                leading: CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFFC2185B),
                  child: Text(
                    userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white, fontSize: 20),
                  ),
                ),
                title: Text(
                  userName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: Color(0xFF444444),
                  ),
                ),
                subtitle: Text(
                  userEmail,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 13,
                  ),
                ),
                trailing: const Icon(
                  Icons.chat_bubble_outline,
                  color: Color(0xFFC2185B),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ChatPage(
                        receiverUserId: userId,
                        receiverName: userName,
                        chatName: userName,
                        isGroup: false,
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}
