import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'group_chat_page.dart';

class GroupListPage extends StatelessWidget {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    final currentUser = _auth.currentUser;

    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Grup Saya')),
        body: Center(child: Text('Pengguna tidak login')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text("Grup Saya"),
        backgroundColor: const Color(0xFFC2185B),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('groups')
            .where('members', arrayContains: currentUser.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text("Terjadi kesalahan"));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          final groups = snapshot.data?.docs ?? [];

          if (groups.isEmpty) {
            return Center(child: Text("Belum bergabung di grup manapun"));
          }

          return ListView.builder(
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final groupData = groups[index].data() as Map<String, dynamic>;
              final groupId = groups[index].id;
              final groupName = groupData['name'] ?? 'Grup';

              return ListTile(
                title: Text(groupName),
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFC2185B),
                  child: Text(groupName[0].toUpperCase(),
                      style: TextStyle(color: Colors.white)),
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) {
                  if (value == 'tambah') {
                    _showTambahAnggotaDialog(context, groupId);
                  } else if (value == 'lihat') {
                    _showLihatAnggotaDialog(context, groupId);
                  }
                  },
                  itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'tambah',
                    child: Text('Tambah Anggota'),
                  ),
                  PopupMenuItem(
                    value: 'lihat',
                    child: Text('Lihat Anggota'),
                  ),
                  ],
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GroupChatPage(
                        groupId: groupId,
                        groupName: groupName,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  void _showTambahAnggotaDialog(BuildContext context, String groupId) async {
    final groupDoc =
        await FirebaseFirestore.instance.collection('groups').doc(groupId).get();
    final currentMembers = List<String>.from(groupDoc.data()?['members'] ?? []);

    final usersSnapshot =
        await FirebaseFirestore.instance.collection('users').get();
    final allUsers = usersSnapshot.docs.map((doc) {
      final data = doc.data();
      return {
        'uid': doc.id,
        'name': data['name'] ?? 'Tanpa Nama',
        'email': data['email'] ?? '',
      };
    }).toList();

    final availableUsers = allUsers
        .where((user) => !currentMembers.contains(user['uid']))
        .toList();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Pilih Anggota untuk Ditambahkan'),
          content: Container(
            width: double.maxFinite,
            height: 300,
            child: availableUsers.isEmpty
                ? Center(child: Text('Semua pengguna sudah tergabung'))
                : ListView.builder(
                    itemCount: availableUsers.length,
                    itemBuilder: (context, index) {
                      final user = availableUsers[index];
                      return ListTile(
                        title: Text(user['name']),
                        subtitle: Text(user['email']),
                        onTap: () async {
                          await FirebaseFirestore.instance
                              .collection('groups')
                              .doc(groupId)
                              .update({
                            'members': FieldValue.arrayUnion([user['uid']])
                          });
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content:
                                    Text('${user['name']} berhasil ditambahkan')),
                          );
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              child: Text('Tutup'),
              onPressed: () => Navigator.pop(context),
            )
          ],
        );
      },
    );
  }
  void _showLihatAnggotaDialog(BuildContext context, String groupId) async {
  final groupDoc =
      await FirebaseFirestore.instance.collection('groups').doc(groupId).get();
  final memberIds = List<String>.from(groupDoc.data()?['members'] ?? []);

  final usersSnapshot = await FirebaseFirestore.instance
      .collection('users')
      .where(FieldPath.documentId, whereIn: memberIds)
      .get();

  final members = usersSnapshot.docs.map((doc) {
    final data = doc.data();
    return {
      'name': data['name'] ?? 'Tanpa Nama',
      'email': data['email'] ?? '',
    };
  }).toList();

  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text('Anggota Grup'),
        content: Container(
          width: double.maxFinite,
          height: 300,
          child: members.isEmpty
              ? Center(child: Text('Belum ada anggota'))
              : ListView.builder(
                  itemCount: members.length,
                  itemBuilder: (context, index) {
                    final user = members[index];
                    return ListTile(
                      title: Text(user['name']),
                      subtitle: Text(user['email']),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            child: Text('Tutup'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      );
    },
  );
}
}
