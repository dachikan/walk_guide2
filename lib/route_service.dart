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
      print('[RouteService] カスタムルート取得開始');
      final directory = await getApplicationDocumentsDirectory();
      print('[RouteService] ディレクトリ: ${directory.path}');
      
      final dirEntity = Directory(directory.path);
      final exists = await dirEntity.exists();
      print('[RouteService] ディレクトリ存在: $exists');
      
      final files = await dirEntity
          .list()
          .where((entity) => entity.path.endsWith('.csv'))
          .toList();
      
      print('[RouteService] 見つかったCSVファイル数: ${files.length}');
      for (var file in files) {
        print('[RouteService] - ${file.path}');
      }
      
      final routes = files.map((file) {
        final fileName = file.path.split(Platform.pathSeparator).last;
        final routeName = fileName.replaceAll('.csv', '');
        print('[RouteService] RouteInfo作成: $fileName -> $routeName');
        return RouteInfo(
          fileName: fileName,
          displayName: routeName,
          description: 'カスタムルート',
          isCustom: true,
        );
      }).toList();
      
      print('[RouteService] カスタムルート数: ${routes.length}');
      return routes;
    } catch (e, stackTrace) {
      print('[RouteService] カスタムルート取得エラー: $e');
      print('[RouteService] スタックトレース: $stackTrace');
      return [];
    }
  }

  /// CSVファイルからルートを読み込む（アセットまたはカスタム）
  static Future<WalkRoute> loadRoute(String fileName, {bool isCustom = false}) async {
    try {
      print('[RouteService] ルート読み込み開始');
      print('[RouteService] ファイル名: $fileName');
      print('[RouteService] カスタム: $isCustom');
      
      String csvString;
      
      if (isCustom) {
        // カスタムルート（ドキュメントディレクトリから）
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$fileName');
        print('[RouteService] カスタムルートパス: ${file.path}');
        
        final exists = await file.exists();
        print('[RouteService] ファイル存在: $exists');
        
        if (!exists) {
          throw Exception('ファイルが見つかりません: ${file.path}');
        }
        
        csvString = await file.readAsString();
        print('[RouteService] ファイル読み込み完了（${csvString.length}文字）');
      } else {
        // アセットルート
        print('[RouteService] アセットルートパス: assets/routes/$fileName');
        csvString = await rootBundle.loadString('assets/routes/$fileName');
        print('[RouteService] アセット読み込み完了（${csvString.length}文字）');
      }
      
      print('[RouteService] ===== CSV内容デバッグ =====');
      print('[RouteService] CSV全文:');
      print(csvString);
      print('[RouteService] CSV文字数: ${csvString.length}');
      print('[RouteService] 改行コード確認: ${csvString.replaceAll('\n', '[LF]').replaceAll('\r', '[CR]')}');
      print('[RouteService] ===== CSV内容ここまで =====');
      
      // 改行コードを統一（\r\nや\rを\nに変換）
      final normalizedCsv = csvString.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      
      final csvData = const CsvToListConverter(eol: '\n').convert(normalizedCsv);
      print('[RouteService] CSV解析完了（${csvData.length}行）');

      final points = <NaviPoint>[];
      // ヘッダー行をスキップ
      for (int i = 1; i < csvData.length; i++) {
        final row = csvData[i];
        if (row.length >= 6) {
          points.add(NaviPoint.fromCsv(row));
        }
      }
      
      print('[RouteService] 地点数: ${points.length}');
      for (var point in points) {
        print('[RouteService] - 地点${point.no}: ${point.message} (${point.latitude}, ${point.longitude})');
      }

      final routeName = fileName.replaceAll('.csv', '');
      print('[RouteService] ルート作成完了: $routeName');
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
