import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'walking_route.dart';

/// ルートCSVファイル管理サービス
class RouteService {
    /// ドキュメントディレクトリのパスを返す（デバッグ用）
    static Future<String> getAppDocDirectoryPath() async {
      final directory = await getApplicationDocumentsDirectory();
      return directory.path;
    }
  /// 利用可能なルート一覧を取得（アセット＋カスタム）
  static Future<List<RouteInfo>> getAvailableRoutes() async {
    final routes = <RouteInfo>[];
    
    // アセットルート（組み込み）
    routes.addAll([
      RouteInfo(
        fileName: 'home_route.csv',
        displayName: '自宅ルート',
        description: '自宅付近の短いルート',
        isCustom: false,
      ),
      RouteInfo(
        fileName: 'friend_home.csv',
        displayName: '友人宅ルート',
        description: '友人宅までの通過点ルート',
        isCustom: false,
      ),
      RouteInfo(
        fileName: 'express_bus_stop.csv',
        displayName: '高速バス停ルート',
        description: '高速バス停までの長距離ルート',
        isCustom: false,
      ),
    ]);

    // カスタムルート（ユーザー作成）
    final customRoutes = await _getCustomRoutes();
    routes.addAll(customRoutes);
    
    return routes;
  }

  /// カスタムルート一覧を取得
  static Future<List<RouteInfo>> _getCustomRoutes() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final dirEntity = Directory(directory.path);
      
      final files = await dirEntity
          .list()
          .where((entity) => entity.path.endsWith('.csv'))
          .toList();
      
      return files.map((file) {
        final fileName = file.path.split(Platform.pathSeparator).last;
        final routeName = fileName.replaceAll('.csv', '');
        return RouteInfo(
          fileName: fileName,
          displayName: routeName,
          description: 'カスタムルート',
          isCustom: true,
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// CSVファイルからルートを読み込む（アセットまたはカスタム）
  static Future<WalkRoute> loadRoute(String fileName, {bool isCustom = false}) async {
    try {
      String csvString;
      
      if (isCustom) {
        // カスタムルート（ドキュメントディレクトリから）
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$fileName');
        csvString = await file.readAsString();
      } else {
        // アセットルート
        csvString = await rootBundle.loadString('assets/routes/$fileName');
      }
      
      final csvData = const CsvToListConverter().convert(csvString);

      final points = <NaviPoint>[];
      // ヘッダー行をスキップ
      for (int i = 1; i < csvData.length; i++) {
        final row = csvData[i];
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
  static Future<void> saveRoute(WalkRoute route, String fileName) async {
    try {
      print('[RouteService] 保存処理開始');
      final directory = await getApplicationDocumentsDirectory();
      print('[RouteService] ディレクトリ取得: ${directory.path}');
      
      final file = File('${directory.path}/$fileName');
      print('[RouteService] ファイルパス: ${file.path}');

      // CSV形式で保存（ヘッダー付き）
      final csvString = route.toCsv();
      print('[RouteService] CSV生成完了（${csvString.length}文字）');
      
      await file.writeAsString(csvString);
      print('[RouteService] ファイル書き込み完了');
      
      // 保存確認
      final exists = await file.exists();
      print('[RouteService] ファイル存在確認: $exists');
      
    } catch (e, stackTrace) {
      print('[RouteService] エラー発生: $e');
      print('[RouteService] スタックトレース: $stackTrace');
      throw Exception('ルート保存エラー: $e');
    }
  }

  /// カスタムルートを削除
  static Future<void> deleteRoute(String fileName) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$fileName');
      
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      throw Exception('ルート削除エラー: $e');
    }
  }
}

/// ルート情報（一覧表示用）
class RouteInfo {
  final String fileName;
  final String displayName;
  final String description;
  final bool isCustom; // カスタムルートかどうか

  RouteInfo({
    required this.fileName,
    required this.displayName,
    required this.description,
    this.isCustom = false,
  });
}
