import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hay_chat/pages/home_page.dart';

class CreateGroupPage extends StatefulWidget {
  @override
  _CreateGroupPageState createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  final TextEditingController _groupNameController = TextEditingController();
  List<String> selectedUserIds = [];
  final currentUser = FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    if (currentUser != null && !selectedUserIds.contains(currentUser!.uid)) {
      selectedUserIds.add(currentUser!.uid); // Tambahkan pembuat grup
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Buat Grup"),
        backgroundColor: const Color(0xFFC2185B),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _groupNameController,
              decoration: const InputDecoration(labelText: "Nama Grup"),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return CircularProgressIndicator();
                final users = snapshot.data!.docs;
                return ListView.builder(
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final user = users[index];
                    final userId = user.id;
                    final userData = user.data() as Map<String, dynamic>;

                    if (userId == currentUser?.uid) return SizedBox.shrink(); // skip self

                    return CheckboxListTile(
                      title: Text(userData['name'] ?? 'User'),
                      subtitle: Text(userData['email'] ?? ''),
                      value: selectedUserIds.contains(userId),
                      onChanged: (selected) {
                        setState(() {
                          if (selected == true) {
                            selectedUserIds.add(userId);
                          } else {
                            selectedUserIds.remove(userId);
                          }
                        });
                      },
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: _createGroup,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFC2185B),
              ),
              child: const Text("Buat Grup"),
            ),
          )
        ],
      ),
    );
  }

  void _createGroup() async {
    final groupName = _groupNameController.text.trim();
    if (groupName.isEmpty || selectedUserIds.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Isi nama grup dan pilih minimal 1 anggota.")),
      );
      return;
    }

    final groupDoc = await FirebaseFirestore.instance.collection('groups').add({
      'name': groupName,
      'members': selectedUserIds,
      'createdAt': Timestamp.now(),
      'createdBy': currentUser!.uid,
    });

    // Tambahkan ke setiap user
    for (String uid in selectedUserIds) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('groups')
          .doc(groupDoc.id)
          .set({
        'groupId': groupDoc.id,
        'groupName': groupName,
      });
    }

    Navigator.pop(context);
  }
}
