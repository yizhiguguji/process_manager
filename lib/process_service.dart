// process_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// 代表一个可被管理进程的信息
class ProcessInfo extends ChangeNotifier {
  String name;
  String path;
  String args;
  bool isRunning;
  bool autoStart;
  final List<String> logs = [];
  Process? process;

  ProcessInfo({
    required this.name,
    required this.path,
    required this.args,
    this.isRunning = false,
    this.autoStart = false,
  });

  /// 添加一行日志
  void addLog(String log) {
    // 限制日志数量，防止内存无限增长
    if (logs.length > 1000) {
      logs.removeAt(0);
    }
    logs.add(log);
    notifyListeners();
  }

  /// 清空日志
  void clearLogs() {
    logs.clear();
    notifyListeners();
  }

  // 用于 JSON 序列化的方法
  Map<String, dynamic> toJson() => {
    'name': name,
    'path': path,
    'args': args,
    'autoStart': autoStart,
  };

  // 用于 JSON 反序列化的工厂构造函数
  factory ProcessInfo.fromJson(Map<String, dynamic> json) {
    return ProcessInfo(
      name: json['name'] ?? '未命名',
      path: json['path'] ?? '',
      args: json['args'] ?? '',
      autoStart: json['autoStart'] ?? false,
    );
  }
}

/// 负责启动和停止进程的服务类
class ProcessService {
  /// 启动一个进程
  Future<void> startProcess(ProcessInfo pInfo) async {
    if (pInfo.isRunning) return;
    if (pInfo.path.isEmpty) {
      throw '程序路径不能为空';
    }

    try {
      String executablePath = pInfo.path.trim(); // 去除前后空格

      // 只有当路径包含路径分隔符、点，或者以'~'开头时，我们才认为它是一个“路径”并尝试解析。
      // 否则，我们认为它是一个系统命令 (如 'dart', 'node')，保持原样让系统去PATH中查找。
      bool isLikelyAPath = executablePath.contains('/') ||
          executablePath.contains('\\') ||
          executablePath.contains('.') ||
          executablePath.startsWith('~');

      if (isLikelyAPath) {
        // 处理 '~' 用户主目录 (macOS/Linux)
        if (Platform.isMacOS || Platform.isLinux) {
          if (executablePath.startsWith('~/')) {
            final homeDir = Platform.environment['HOME'];
            if (homeDir != null) {
              executablePath = executablePath.replaceFirst('~', homeDir);
            }
          }
        }

        // 将可能是相对路径的程序路径，转换为绝对路径
        if (!p.isAbsolute(executablePath)) {
          executablePath = p.absolute(executablePath);
        }

        // 检查解析后的文件是否存在
        if (!await File(executablePath).exists()) {
          throw '程序文件不存在: $executablePath';
        }
      }

      // --- 2. 解析参数 ---
      // (不对参数路径进行转换，因为 shell 会更好地处理相对路径和特殊字符)
      final List<String> resolvedArgs = pInfo.args.split(' ').where((s) => s.isNotEmpty).toList();

      // --- 3. 获取工作目录  ---
      // 只有当它是路径时，我们才能安全地获取目录。如果是命令，则使用当前目录。
      final String workingDirectory = isLikelyAPath ? p.dirname(executablePath) : '.';

      // --- 4. 启动进程 ---
      // 为了解决 scrcpy 等命令行工具因输出缓冲导致的日志顺序错乱问题，
      // 我们采用 runInShell: true。这会通过系统 shell 启动进程，
      // 模拟一个更接近真实终端的环境，通常能“说服”被调用程序禁用缓冲，从而按正确顺序实时输出日志。
      final process = await Process.start(
        executablePath, // 程序或命令
        resolvedArgs,   // 参数列表
        workingDirectory: workingDirectory,
        runInShell: true, // 关键：在 shell 中运行
      );

      pInfo.isRunning = true;
      pInfo.process = process;
      pInfo.clearLogs();
      pInfo.addLog('进程已启动，程序: $executablePath');
      pInfo.addLog('工作目录: $workingDirectory\n');

      // 使用 LineSplitter 来确保我们按行处理输出
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        pInfo.addLog(line);
      });

      process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        pInfo.addLog('[错误] $line');
      });

      process.exitCode.then((exitCode) {
        pInfo.addLog('\n进程已退出，退出码: $exitCode');
        pInfo.isRunning = false;
        pInfo.process = null;
        pInfo.notifyListeners();
      });

      pInfo.notifyListeners();

    } catch (e) {
      pInfo.isRunning = false;
      final errorMessage = '启动失败: ${e.toString()}';
      pInfo.addLog(errorMessage);
      throw errorMessage;
    }
  }

  /// 停止一个进程
  Future<void> stopProcess(ProcessInfo pInfo) async {
    if (pInfo.isRunning && pInfo.process != null) {
      final killed = pInfo.process!.kill();
      if (killed) {
        pInfo.addLog('\n命令已发送：停止进程...');
      } else {
        pInfo.addLog('\n错误：无法发送停止命令，进程可能已经退出。');
      }
      // 不论命令是否发送成功，都将状态更新为非运行
      pInfo.isRunning = false;
      pInfo.process = null;
      pInfo.notifyListeners();
    }
  }
}
