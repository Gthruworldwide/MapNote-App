import 'dart:math' as math;

/// Immutable 3D vector for kinematic calculations in the Anti-Gravity engine.
class Vector3D {
  final double x;
  final double y;
  final double z;

  const Vector3D(this.x, this.y, this.z);

  static const Vector3D zero = Vector3D(0.0, 0.0, 0.0);
  static const Vector3D unitX = Vector3D(1.0, 0.0, 0.0);
  static const Vector3D unitY = Vector3D(0.0, 1.0, 0.0);
  static const Vector3D unitZ = Vector3D(0.0, 0.0, 1.0);

  Vector3D operator +(Vector3D other) =>
      Vector3D(x + other.x, y + other.y, z + other.z);

  Vector3D operator -(Vector3D other) =>
      Vector3D(x - other.x, y - other.y, z - other.z);

  Vector3D operator -() => Vector3D(-x, -y, -z);

  Vector3D operator *(double scalar) =>
      Vector3D(x * scalar, y * scalar, z * scalar);

  Vector3D operator /(double scalar) =>
      scalar != 0 ? Vector3D(x / scalar, y / scalar, z / scalar) : zero;

  double get lengthSquared => x * x + y * y + z * z;

  double get length => math.sqrt(lengthSquared);

  Vector3D normalize() {
    final len = length;
    return len > 0.000001 ? this / len : zero;
  }

  double dot(Vector3D other) => x * other.x + y * other.y + z * other.z;

  Vector3D cross(Vector3D other) => Vector3D(
        y * other.z - z * other.y,
        z * other.x - x * other.z,
        x * other.y - y * other.x,
      );

  static Vector3D lerp(Vector3D a, Vector3D b, double t) =>
      a * (1.0 - t) + b * t;

  @override
  String toString() =>
      'Vector3D(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)}, ${z.toStringAsFixed(2)})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Vector3D &&
          runtimeType == other.runtimeType &&
          x == other.x &&
          y == other.y &&
          z == other.z;

  @override
  int get hashCode => Object.hash(x, y, z);
}
