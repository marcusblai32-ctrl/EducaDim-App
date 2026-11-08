import 'package:flutter/material.dart';

/// Bloc de chargement statique (aucune animation).
class Skeleton extends StatelessWidget {
  const Skeleton({super.key, this.height = 16, this.width, this.radius = 10});
  final double height, radius;
  final double? width;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}

/// Trois cartes « fantômes » : aperçu de la mise en page pendant le chargement.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 3});
  final int count;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: count,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (_, __) => Card(
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
          AspectRatio(aspectRatio: 16 / 9, child: Skeleton(height: double.infinity, radius: 0)),
          Padding(
            padding: EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Skeleton(height: 12, width: 90),
              SizedBox(height: 10),
              Skeleton(height: 18),
              SizedBox(height: 8),
              Skeleton(height: 12, width: 150),
            ]),
          ),
        ]),
      ),
    );
  }
}
