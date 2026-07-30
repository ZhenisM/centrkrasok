class Section {
  final String id;
  final String name;
  final String? parentId;
  final String? image;
  final List<Section> children;

  Section({
    required this.id,
    required this.name,
    this.parentId,
    this.image,
    required this.children,
  });

  factory Section.fromJson(Map<String, dynamic> json) {
    final childrenJson = json['CHILDREN'] as List<dynamic>? ?? [];
    final childrenList = childrenJson.map((e) => Section.fromJson(e)).toList();

    final rawImage = json['IMAGE'] as String?;

    return Section(
      id: json['ID'].toString(),
      name: json['NAME'],
      parentId: json['PARENT_ID']?.toString(),
      image: (rawImage != null && rawImage.isNotEmpty) ? rawImage : null,
      children: childrenList,
    );
  }
}
