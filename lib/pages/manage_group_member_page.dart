import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ManageGroupMembersPage extends StatefulWidget {
  final String groupId;
  final String groupName;

  ManageGroupMembersPage({required this.groupId, required this.groupName});

  @override
  State<ManageGroupMembersPage> createState() => _ManageGroupMembersPageState();
}

class _ManageGroupMembersPageState extends State<ManageGroupMembersPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  List<String> currentMembers = [];
  List<String> selectedUsersToAdd = [];

  @override
  void initState() {
    super.initState();
    _loadGroupMembers();
  }

  Future<void> _loadGroupMembers() async {
    DocumentSnapshot groupSnapshot =
        await _firestore.collection('groups').doc(widget.groupId).get();
    List<dynamic> members = groupSnapshot['members'];
    setState(() {
      currentMembers = List<String>.from(members);
    });
  }

  Future<void> _addMembers() async {
    if (selectedUsersToAdd.isEmpty) return;

    // Update group document
    await _firestore.collection('groups').doc(widget.groupId).update({
      'members': FieldValue.arrayUnion(selectedUsersToAdd),
    });

    // Tambahkan ke masing-masing user/groups
    for (String uid in selectedUsersToAdd) {
      await _firestore.collection('users').doc(uid).collection('groups').doc(widget.groupId).set({
        'groupId': widget.groupId,
        'groupName': widget.groupName,
      });
    }

    await _loadGroupMembers();
    selectedUsersToAdd.clear();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Anggota ditambahkan.")));
  }

  Future<void> _removeMember(String userId) async {
    if (userId == _auth.currentUser!.uid) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Kamu tidak bisa menghapus diri sendiri.")));
      return;
    }

    await _firestore.collection('groups').doc(widget.groupId).update({
      'members': FieldValue.arrayRemove([userId]),
    });

    await _firestore.collection('users').doc(userId).collection('groups').doc(widget.groupId).delete();

    await _loadGroupMembers();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Anggota dihapus.")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Kelola Anggota: ${widget.groupName}"),
        backgroundColor: const Color(0xFFC2185B),
      ),
      body: Column(
        children: [
          const SizedBox(height: 10),
          const Text("Anggota Saat Ini", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Expanded(
            child: ListView.builder(
              itemCount: currentMembers.length,
              itemBuilder: (context, index) {
                String uid = currentMembers[index];
                return FutureBuilder<DocumentSnapshot>(
                  future: _firestore.collection('users').doc(uid).get(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return SizedBox();
                    var user = snapshot.data!;
                    return ListTile(
                      title: Text(user['name'] ?? 'User'),
                      subtitle: Text(user['email'] ?? ''),
                      trailing: IconButton(
                        icon: Icon(Icons.remove_circle, color: Colors.red),
                        onPressed: () => _removeMember(uid),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const Divider(),
          const Text("Tambah Anggota Baru", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('users').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
                final users = snapshot.data!.docs;
                final availableUsers = users.where((doc) => !currentMembers.contains(doc.id)).toList();
                return ListView.builder(
                  itemCount: availableUsers.length,
                  itemBuilder: (context, index) {
                    final user = availableUsers[index];
                    final userId = user.id;
                    final userData = user.data() as Map<String, dynamic>;

                    return CheckboxListTile(
                      title: Text(userData['name'] ?? 'User'),
                      subtitle: Text(userData['email'] ?? ''),
                      value: selectedUsersToAdd.contains(userId),
                      onChanged: (selected) {
                        setState(() {
                          if (selected == true) {
                            selectedUsersToAdd.add(userId);
                          } else {
                            selectedUsersToAdd.remove(userId);
                          }
                        });
                      },
                    );
                  },
                );
              },
            ),
          ),
          ElevatedButton(
            onPressed: _addMembers,
            child: Text("Tambah ke Grup"),
            style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFC2185B)),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}