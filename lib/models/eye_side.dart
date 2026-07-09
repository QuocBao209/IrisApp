enum EyeSide { left, right }

extension EyeSideX on EyeSide {
  String get value => this == EyeSide.left ? 'left' : 'right';
  String get label => this == EyeSide.left ? 'MẮT TRÁI' : 'MẮT PHẢI';
}