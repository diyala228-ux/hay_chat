class GroupModel {
  String groupId;
  String groupName;
  List<String> members;

  GroupModel({required this.groupId, required this.groupName, required this.members});

  // Method untuk mengkonversi data dari JSON
  factory GroupModel.fromJson(Map<String, dynamic> json) {
    return GroupModel(
      groupId: json['groupId'],
      groupName: json['groupName'],
      members: List<String>.from(json['members']),
    );
  }

  // Method untuk mengkonversi data ke JSON
  Map<String, dynamic> toJson() {
    return {
      'groupId': groupId,
      'groupName': groupName,
      'members': members,
    };
  }
}