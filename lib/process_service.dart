import 'dart:io';
import 'package:process_run/process_run.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';

class ProcessInfo extends ChangeNotifier {
  static const int maxOutputLength = 1000;
  String name;
  String path;
  String args;
  bool isRunning;
  Process? process;
  final List<String> _outputLines = [];

  ProcessInfo({
    required this.name,
    required this.path,
    required this.args,
    this.isRunning = false,
    this.process,
  });

  void updateStatus(bool status) {
    isRunning = status;
    notifyListeners();
  }

  String getRecentOutput(int lines) {
    if (_outputLines.isEmpty) return '';
    final start = _outputLines.length > lines ? 
                 _outputLines.length - lines : 0;
    return _outputLines.sublist(start).join('\n');
  }

  String get output => _outputLines.join('\n');

  void addOutput(String text) {
    _outputLines.add(text);
    // 保持最新的日志，超出限制时删除旧的
    while (_outputLines.length > maxOutputLength) {
      _outputLines.removeAt(0);
    }
    notifyListeners();
  }

  void clearOutput() {
    _outputLines.clear();
    notifyListeners();
  }
}

class ProcessService {
  Future<void> startProcess(ProcessInfo info) async {
    if (info.isRunning) return;
    
    try {
      // Validate input path
      if (info.path.trim().isEmpty) {
        throw ProcessException('', [], '请输入程序路径');
      }

      // 改进路径处理
      String expandedPath = info.path.trim();
      if (expandedPath.startsWith('~/')) {
        final home = Platform.environment['HOME'];
        if (home != null) {
          expandedPath = path.join(home, expandedPath.substring(2));
        }
      }
      
      // 确保路径规范化
      expandedPath = path.normalize(expandedPath);
      debugPrint('Attempting to start process at: $expandedPath');
      
      // 检查文件是否存在并且可执行
      final file = File(expandedPath);
      if (!file.existsSync()) {
        throw ProcessException(
          expandedPath,
          [],
          '可执行文件未找到，请检查路径: $expandedPath',
        );
      }

      final String workingDirectory = path.dirname(expandedPath);
      
      final process = await Process.start(
        expandedPath,
        info.args.split(' ').where((arg) => arg.isNotEmpty).toList(),
        workingDirectory: workingDirectory,
      );
      
      info.process = process;
      info.updateStatus(true);

      // 处理标准输出
      process.stdout.transform(const SystemEncoding().decoder).listen(
        (data) {
          info.addOutput(data.trim());  // 移除了 '输出:' 前缀
          debugPrint('Process stdout: $data');
        },
        onError: (error) {
          debugPrint('输出错误: $error');
        }
      );
      
      // 处理错误输出
      process.stderr.transform(const SystemEncoding().decoder).listen(
        (data) {
          info.addOutput('${data.trim()}');  // 只在错误输出添加前缀
          debugPrint('Process stderr: $data');
        },
        onError: (error) {
          debugPrint('错误输出错误: $error');
        }
      );

      // 监听进程退出
      process.exitCode.then((code) {
        debugPrint('进程退出，退出码: $code');
        info.updateStatus(false);
        info.process = null;
      }).catchError((error) {
        debugPrint('进程错误: $error');
        info.updateStatus(false);
        info.process = null;
      });
      
    } catch (e) {
      debugPrint('启动进程错误: $e');
      info.updateStatus(false);
      info.process = null;
      info.addOutput('错误: $e\n');  // Add error to output
      rethrow;
    }
  }

  Future<void> stopProcess(ProcessInfo info) async {
    if (!info.isRunning || info.process == null) return;
    
    try {
      info.process!.kill();
      info.updateStatus(false);
      info.process = null;
      info.addOutput('进程已停止\n');
    } catch (e) {
      debugPrint('停止进程错误: $e');
      info.addOutput('停止进程错误: $e\n');
      rethrow;
    }
  }
}