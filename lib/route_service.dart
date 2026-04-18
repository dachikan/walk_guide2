import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'walking_route.dart';

/// ルートCSVファイル管理サービス
class RouteService {
  /// 利用可能なルート一覧を取得
  static Future<List<RouteInfo>> getAvailableRoutes() async {
    final routes = [
      RouteInfo(
        fileName: 'home_route.csv',
        displayName: '自宅ルート',
        description: '自宅付近の短いルート',
      ),
      RouteInfo(
        fileName: 'friend_home.csv',
        displayName: '友人宅ルート',
        description: '友人宅までの通過点ルート',
      ),
      RouteInfo(
        fileName: 'express_bus_stop.csv',
        displayName: '高速バス停ルート',
        description: '高速バス停までの長距離ルート',
      ),
    ];
    return routes;
  }

  /// CSVファイルからルートを読み込む
  static Future<WalkRoute> loadRoute(String fileName) async {
    try {
      final csvString = await rootBundle.loadString('assets/routes/$fileName');
      final csvData = const CsvToListConverter().convert(csvString);

      final points = <NaviPoint>[];
      for (final row in csvData) {
        if (row.length >= 6) {
          points.add(NaviPoint.fromCsv(row));
        }
      }

      final routeName = fileName.replaceAll('.csv', '');
      return WalkRoute(name: routeName, points: points);
    } catch (e) {
      throw Exception('ルート読み込みエラー: $e');
    }
  }

  /// 新しいルートをCSVファイルとして保存
  static Future<void> saveRoute(WalkRoute route) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/${route.name}.csv');

      final csvData = route.points.map((point) {
        return [
          point.no,
          point.latitude,
          point.longitude,
          point.heading,
          point.triggerDistance,
          point.message,
        ];
      }).toList();

      final csvString =
          const ListToCsvConverter().convert(csvData, fieldDelimiter: ',');

      await file.writeAsString(csvString);
    } catch (e) {
      throw Exception('ルート保存エラー: $e');
    }
  }
}

/// ルート情報（一覧表示用）
class RouteInfo {
  final String fileName;
  final String displayName;
  final String description;

  RouteInfo({
    required this.fileName,
    required this.displayName,
    required this.description,
  });
}
