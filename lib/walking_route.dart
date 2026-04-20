import 'package:geolocator/geolocator.dart';

/// ルート上の地点データ
class NaviPoint {
  final int no;
  final double latitude;
  final double longitude;
  final double heading; // 方位（将来的な拡張用）
  final double triggerDistance; // 案内を開始する距離(m)
  final String message; // 読み上げるメッセージ

  NaviPoint({
    required this.no,
    required this.latitude,
    required this.longitude,
    this.heading = 0.0,
    this.triggerDistance = 10.0,
    required this.message,
  });

  /// CSV一行からNaviPointを作成
  /// フォーマット: no, 緯度, 経度, 方位, 距離, メッセージ
  factory NaviPoint.fromCsv(List<dynamic> row) {
    return NaviPoint(
      no: int.tryParse(row[0].toString()) ?? 0,
      latitude: double.tryParse(row[1].toString()) ?? 0.0,
      longitude: double.tryParse(row[2].toString()) ?? 0.0,
      heading: double.tryParse(row[3].toString()) ?? 0.0,
      triggerDistance: double.tryParse(row[4].toString()) ?? 10.0,
      message: row.length > 5 ? row[5].toString() : '地点に近づきました',
    );
  }

  /// 現在地との距離を計算(m)
  double distanceTo(Position currentPosition) {
    return Geolocator.distanceBetween(
      currentPosition.latitude,
      currentPosition.longitude,
      latitude,
      longitude,
    );
  }

  /// 現在地からこの地点への方位を計算（度）
  double bearingFrom(Position currentPosition) {
    return Geolocator.bearingBetween(
      currentPosition.latitude,
      currentPosition.longitude,
      latitude,
      longitude,
    );
  }

  /// イミュータブル更新用のcopyWith
  NaviPoint copyWith({
    int? no,
    double? latitude,
    double? longitude,
    double? heading,
    double? triggerDistance,
    String? message,
  }) {
    return NaviPoint(
      no: no ?? this.no,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      heading: heading ?? this.heading,
      triggerDistance: triggerDistance ?? this.triggerDistance,
      message: message ?? this.message,
    );
  }

  /// CSV形式の文字列に変換
  String toCsvRow() {
    return '$no,$latitude,$longitude,$heading,$triggerDistance,$message';
  }
}

/// 歩行ルート（地点の集合）
class WalkRoute {
  final String name;
  final List<NaviPoint> points;

  WalkRoute({required this.name, required this.points});

  /// イミュータブル更新用のcopyWith
  WalkRoute copyWith({
    String? name,
    List<NaviPoint>? points,
  }) {
    return WalkRoute(
      name: name ?? this.name,
      points: points ?? this.points,
    );
  }

  /// CSV形式の文字列に変換
  String toCsv() {
    final buffer = StringBuffer();
    buffer.writeln('地点番号,緯度,経度,方位,トリガー距離,メッセージ');
    for (final point in points) {
      buffer.writeln(point.toCsvRow());
    }
    return buffer.toString();
  }

  /// 総距離を計算（メートル）
  double getTotalDistance() {
    if (points.length < 2) return 0.0;
    double total = 0.0;
    for (int i = 0; i < points.length - 1; i++) {
      total += Geolocator.distanceBetween(
        points[i].latitude,
        points[i].longitude,
        points[i + 1].latitude,
        points[i + 1].longitude,
      );
    }
    return total;
  }
}
