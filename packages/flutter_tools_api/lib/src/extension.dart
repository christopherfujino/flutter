/// A Flutter CLI Tool Extension.
abstract class Extension {
  const Extension({required this.name});
  final String name;
}

abstract class TemplateExtension extends Extension {
  const TemplateExtension({required super.name});
}

class SkeletonExtension extends TemplateExtension {
  const SkeletonExtension() : super(name: 'skeleton_template');
}
