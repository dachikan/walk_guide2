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
}

/// 歩行ルート（地点の集合）
class WalkRoute {
  final String name;
  final List<NaviPoint> points;

  WalkRoute({required this.name, required this.points});
}
