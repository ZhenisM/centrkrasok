class Section {
  final String id;
  final String name;
  final String? parentId;
  final List<Section> children;

  Section({
    required this.id,
    required this.name,
    this.parentId,
    required this.children,
  });

  factory Section.fromJson(Map<String, dynamic> json) {
    final childrenJson = json['CHILDREN'] as List<dynamic>? ?? [];
    final childrenList = childrenJson.map((e) => Section.fromJson(e)).toList();

    return Section(
      id: json['ID'].toString(),
      name: json['NAME'],
      parentId: json['PARENT_ID']?.toString(),
      children: childrenList,
    );
  }
}