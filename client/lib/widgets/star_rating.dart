import 'package:flutter/material.dart';

/// Read-only row of 5 stars for a rating (0-5, half-star aware). Shared
/// between the public trace page's review list and the admin apiary
/// ratings screen, so both render averages identically.
class StarRating extends StatelessWidget {
  final double rating;
  final double size;

  const StarRating({super.key, required this.rating, this.size = 20});

  static const Color _color = Color(0xFFB8860B);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = rating >= i + 1;
        final half = !filled && rating > i;
        return Icon(
          half ? Icons.star_half : (filled ? Icons.star : Icons.star_border),
          color: _color,
          size: size,
        );
      }),
    );
  }
}
