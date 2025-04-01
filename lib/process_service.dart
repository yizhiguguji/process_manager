import 'dart:io';
import 'package:process_run/process_run.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:charcode/ascii.dart';
import 'package:gbk_codec/gbk_codec.dart';  // 添加导入

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
    final start = _outputLines.length > lines ? _outputLines.length - lines : 0;
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
  final Map<ProcessInfo, Process> _runningProcesses = {};

  // 添加编码处理方法
  String decodeOutput(List<int> data) {
    try {
      // 首先尝试 UTF-8
      return utf8.decode(data);
    } catch (_) {
      try {
        // UTF-8 失败时尝试 GBK
        return gbk.decode(data);
      } catch (_) {
        // 都失败时使用系统编码
        return const SystemEncoding().decode(data);
      }
    }
  }

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
      process.stdout.listen((List<int> data) {
        final decodedData = decodeOutput(data);
        info.addOutput(decodedData.trim());
        debugPrint('Process stdout: $decodedData');
      }, onError: (error) {
        debugPrint('输出错误: $error');
      });

      // 处理错误输出
      process.stderr.listen((List<int> data) {
        final decodedData = decodeOutput(data);
        info.addOutput(decodedData.trim());
        debugPrint('Process stderr: $decodedData');
      }, onError: (error) {
        debugPrint('错误输出错误: $error');
      });

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
      info.addOutput('错误: $e\n'); // Add error to output
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

  // 添加关闭所有进程的方法
  Future<void> stopAllProcesses() async {
    for (var process in _runningProcesses.values) {
      try {
        process.kill();
      } catch (e) {
        print('停止进程时出错: $e');
      }
    }
    _runningProcesses.clear();
  }
}

// GBK 编码实现
class GbkCodec extends Encoding {
  const GbkCodec();

  @override
  Converter<List<int>, String> get decoder => const GbkDecoder();

  @override
  Converter<String, List<int>> get encoder => throw UnimplementedError();

  @override
  String get name => 'gbk';
}

class GbkDecoder extends Converter<List<int>, String> {
  const GbkDecoder();

  @override
  String convert(List<int> input) {
    try {
      // 由于 Dart 没有内置的 GBK 解码器，这里需要使用第三方库如 'gbk_codec'
      // 请添加依赖: gbk_codec: ^0.4.0
      throw UnimplementedError('请添加 gbk_codec 依赖并实现 GBK 解码');
    } catch (_) {
      return utf8.decode(input, allowMalformed: true);
    }
  }
}
