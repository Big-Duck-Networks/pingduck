/// What the user says a device is. Each field overrides the recognizer's
/// guess for that field; null leaves the guess in place.
class DeviceLabel {
  const DeviceLabel({this.brand, this.model, this.os});

  /// Trims each field and turns blanks into null.
  factory DeviceLabel.clean({String? brand, String? model, String? os}) {
    String? c(String? s) {
      final t = s?.trim();
      return t == null || t.isEmpty ? null : t;
    }

    return DeviceLabel(brand: c(brand), model: c(model), os: c(os));
  }

  final String? brand;
  final String? model;
  final String? os;

  bool get isEmpty => brand == null && model == null && os == null;

  @override
  bool operator ==(Object other) =>
      other is DeviceLabel && other.brand == brand && other.model == model && other.os == os;

  @override
  int get hashCode => Object.hash(brand, model, os);

  @override
  String toString() => 'DeviceLabel($brand, $model, $os)';
}
