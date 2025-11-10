import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'process_service.dart';
import 'dart:io' show Platform;
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isMacOS || Platform.isWindows) {
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      size: Size(800, 600),
      minimumSize: Size(600, 400),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setPreventClose(true);
    });
  }

  final prefs = await SharedPreferences.getInstance();
  final width = prefs.getDouble('window_width') ?? 800.0;
  final height = prefs.getDouble('window_height') ?? 600.0;

  if (Platform.isMacOS || Platform.isWindows) {
    await windowManager.setSize(Size(width, height));
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '进程管理器',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const ProcessManagerHome(),
    );
  }
}

class ProcessManagerHome extends StatefulWidget {
  const ProcessManagerHome({super.key});

  @override
  State<ProcessManagerHome> createState() => _ProcessManagerHomeState();
}

class _ProcessManagerHomeState extends State<ProcessManagerHome> with WindowListener {
  final List<ProcessInfo> processes = [];

  final List<TextEditingController> _nameControllers = [];
  final List<TextEditingController> _pathControllers = [];
  final List<TextEditingController> _argsControllers = [];

  final ProcessService _processService = ProcessService();
  late SharedPreferences _prefs;
  final List<bool> _expansionStates = [];

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);

    SharedPreferences.getInstance().then((prefs) {
      _prefs = prefs;
      final count = _prefs.getInt('process_count') ?? 0;

      setState(() {
        processes.clear();
        _nameControllers.clear();
        _pathControllers.clear();
        _argsControllers.clear();
        _expansionStates.clear(); // <--- 添加：清空展开状态列表
        for (var i = 0; i < count; i++) {
          final name = _prefs.getString('process_${i}_name') ?? '新程序';
          final path = _prefs.getString('process_${i}_path') ?? '';
          final args = _prefs.getString('process_${i}_args') ?? '';
          // 【新增】加载 autoStart 状态
          final autoStart = _prefs.getBool('process_${i}_autoStart') ?? false;

          processes.add(ProcessInfo(
            name: name,
            path: path,
            args: args,
            autoStart: autoStart, // 【新增】应用 autoStart 状态
          ));

          _nameControllers.add(TextEditingController(text: name));
          _pathControllers.add(TextEditingController(text: path));
          _argsControllers.add(TextEditingController(text: args));
          _expansionStates.add(false); // <--- 添加：为每个加载的进程设置默认折叠状态
          processes.last.addListener(() {
            if (mounted) {
              setState(() {});
            }
          });
        }
      });
      // 【新增】在加载配置后执行自动启动
      _runAutoStartProcesses();
    });
  }

  // 【新增】执行自动启动进程的方法
  Future<void> _runAutoStartProcesses() async {
    // 延迟一小段时间，确保UI已经构建完毕
    await Future.delayed(const Duration(milliseconds: 500));

    for (var process in processes) {
      if (process.autoStart && !process.isRunning) {
        try {
          await _processService.startProcess(process);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('自动启动失败: ${process.name} - ${e.toString()}'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }
    }
  }

  // 【修改】保存设置方法，增加 autoStart
  Future<void> _saveSettings(int index) async {
    await _prefs.setString('process_${index}_name', processes[index].name);
    await _prefs.setString('process_${index}_path', processes[index].path);
    await _prefs.setString('process_${index}_args', processes[index].args);
    await _prefs.setBool('process_${index}_autoStart', processes[index].autoStart); // 新增保存 autoStart
    await _prefs.setInt('process_count', processes.length);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    for (var process in processes) {
      if (process.isRunning) {
        _processService.stopProcess(process);
      }
    }
    for (var controller in _nameControllers) {
      controller.dispose();
    }
    for (var controller in _pathControllers) {
      controller.dispose();
    }
    for (var controller in _argsControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        bool hasRunningProcess = processes.any((p) => p.isRunning);
        if (!hasRunningProcess) {
          return true;
        }

        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('确认退出'),
            content: const Text('还有正在运行的进程，确定要退出吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () async {
                  for (var process in processes) {
                    if (process.isRunning) {
                      await _processService.stopProcess(process);
                    }
                  }
                  if (mounted) {
                    Navigator.of(context).pop(true);
                  }
                },
                child: const Text('确定'),
              ),
            ],
          ),
        ) ??
            false;

        return shouldExit;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('进程管理器'),
          actions: [
            ElevatedButton.icon(
              onPressed: processes.any((p) => p.isRunning)
                  ? () async {
                final runningProcesses = processes.where((p) => p.isRunning).toList();
                if (runningProcesses.isEmpty) return;
                for (var process in runningProcesses) {
                  await _processService.stopProcess(process);
                }
              }
                  : null,
              icon: const Icon(Icons.stop_circle, color: Colors.white),
              label: Text('全部停止 (${processes.where((p) => p.isRunning).length})',
                  style: const TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.grey[400],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: processes.any((p) => !p.isRunning)
                  ? () async {
                final stoppedProcesses = processes.where((p) => !p.isRunning).toList();
                if (stoppedProcesses.isEmpty) return;
                for (var process in stoppedProcesses) {
                  try {
                    await _processService.startProcess(process);
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('启动失败: ${process.name} - ${e.toString()}'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              }
                  : null,
              icon: const Icon(Icons.play_circle, color: Colors.white),
              label: Text('全部启动 (${processes.where((p) => !p.isRunning).length})',
                  style: const TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.grey[400],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  processes.add(ProcessInfo(name: '新程序', path: '', args: ''));
                  _nameControllers.add(TextEditingController(text: '新程序'));
                  _pathControllers.add(TextEditingController(text: ''));
                  _argsControllers.add(TextEditingController(text: ''));
                  _expansionStates.add(true); // <--- 新增：添加新进程时，默认为展开状态
                  processes.last.addListener(() {
                    if (mounted) {
                      setState(() {});
                    }
                  });
                  _saveSettings(processes.length - 1);
                });
              },
              icon: const Icon(Icons.add_circle_outline, color: Colors.white),
              label: const Text('添加'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2196F3),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: Column(
              children: List.generate(
                processes.length,
                    (index) {
                      // 在 List.generate(...) 的回调中...
                      final process = processes[index];

                      return Card(
                        margin: const EdgeInsets.only(bottom: 16.0),
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column( // 1. 最外层使用 Column，分为“顶部信息”和“可折叠详情”
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // --- 第一部分：始终显示的顶部信息 ---
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center, // 垂直居中对齐
                                children: [
                                  // --- 左侧：程序名称 ---
                                  Expanded(
                                    child: TextField(
                                      decoration: InputDecoration(
                                        labelText: '程序名称',
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      ),
                                      controller: _nameControllers[index],
                                      onChanged: (value) {
                                        process.name = value;
                                        _saveSettings(index);
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 20), // 名称和按钮组之间的间距

                                  // --- 右侧：统一的操作按钮组 ---
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: process.isRunning ? Colors.red : Colors.green,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    ),
                                    onPressed: () async {
                                      try {
                                        if (process.isRunning) {
                                          await _processService.stopProcess(process);
                                        } else {
                                          await _processService.startProcess(process);
                                        }
                                      } catch (e) {
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                            content: Text(e.toString()),
                                            backgroundColor: Colors.red,
                                          ));
                                        }
                                      }
                                    },
                                    child: Text(process.isRunning ? '停止' : '启动'),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () {
                                      if (process.isRunning) {
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先停止进程再删除')));
                                        return;
                                      }
                                      setState(() {
                                        _nameControllers[index].dispose();
                                        _pathControllers[index].dispose();
                                        _argsControllers[index].dispose();
                                        _nameControllers.removeAt(index);
                                        _pathControllers.removeAt(index);
                                        _argsControllers.removeAt(index);
                                        processes.removeAt(index);
                                        _expansionStates.removeAt(index);

                                        // 正确地更新 SharedPreferences
                                        _prefs.setInt('process_count', processes.length);
                                        for (var i = 0; i < processes.length; i++) {
                                          // 重新保存所有后续进程的信息到新的索引
                                          _saveSettings(i);
                                        }
                                        // 删除最后一个多余的键
                                        _prefs.remove('process_${processes.length}_name');
                                        _prefs.remove('process_${processes.length}_path');
                                        _prefs.remove('process_${processes.length}_args');
                                        _prefs.remove('process_${processes.length}_autoStart');
                                      });
                                    },
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      _expansionStates[index] ? Icons.expand_less : Icons.expand_more,
                                      color: Theme.of(context).primaryColor,
                                    ),
                                    tooltip: _expansionStates[index] ? '收起' : '展开详情',
                                    onPressed: () {
                                      setState(() {
                                        _expansionStates[index] = !_expansionStates[index];
                                      });
                                    },
                                  ),
                                ],
                              ),

                              // --- 第二部分：可折叠的详细信息 ---
                              Visibility(
                                visible: _expansionStates[index],
                                maintainState: true,
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 20.0),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // --- 左侧：详细配置 ---
                                      SizedBox(
                                        width: 400,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // 【已补全】Checkbox, Path, Args 的代码
                                            CheckboxListTile(
                                              title: const Text('启动时自动运行'),
                                              value: process.autoStart,
                                              onChanged: !process.isRunning
                                                  ? (bool? value) {
                                                setState(() {
                                                  process.autoStart = value ?? false;
                                                });
                                                _saveSettings(index);
                                              }
                                                  : null,
                                              controlAffinity: ListTileControlAffinity.leading,
                                              contentPadding: EdgeInsets.zero,
                                            ),
                                            const SizedBox(height: 16),
                                            TextField(
                                              decoration: InputDecoration(
                                                labelText: '程序路径',
                                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                              ),
                                              controller: _pathControllers[index],
                                              enabled: !process.isRunning,
                                              onChanged: (value) {
                                                process.path = value;
                                                _saveSettings(index);
                                              },
                                            ),
                                            const SizedBox(height: 16),
                                            TextField(
                                              decoration: InputDecoration(
                                                labelText: '程序参数',
                                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                              ),
                                              controller: _argsControllers[index],
                                              enabled: !process.isRunning,
                                              onChanged: (value) {
                                                process.args = value;
                                                _saveSettings(index);
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 20),
                                      // --- 右侧：日志区域 ---
                                      Expanded(
                                        child: SizedBox(
                                          height: 320,
                                          child: Stack(
                                            // 【已补全】日志框 (Stack) 的代码
                                            children: [
                                              Container(
                                                width: double.infinity,
                                                height: double.infinity,
                                                padding: const EdgeInsets.all(12.0),
                                                decoration: BoxDecoration(
                                                  color: Colors.black.withOpacity(0.8),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: SingleChildScrollView(
                                                  reverse: true,
                                                  child: SelectableText(
                                                    process.logs.join(),
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontFamily: 'monospace',
                                                      fontSize: 12,
                                                    ),
                                                    scrollPhysics: const NeverScrollableScrollPhysics(),
                                                  ),
                                                ),
                                              ),
                                              Positioned(
                                                top: 8,
                                                right: 8,
                                                child: Material(
                                                  color: Colors.white.withOpacity(0.15),
                                                  borderRadius: BorderRadius.circular(20),
                                                  clipBehavior: Clip.antiAlias,
                                                  child: InkWell(
                                                    onTap: () {
                                                      process.clearLogs();
                                                    },
                                                    child: Container(
                                                      padding: const EdgeInsets.all(6.0),
                                                      child: const Icon(
                                                        Icons.delete_outline,
                                                        color: Colors.white,
                                                        size: 20,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );


                    },
              ),
            ),
          ),
        ),
      ),
    );
  }

  // WindowListener 的实现
  @override
  void onWindowClose() async {
    bool hasRunningProcess = processes.any((p) => p.isRunning);
    bool isPreventClose = await windowManager.isPreventClose();

    if (hasRunningProcess && isPreventClose) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认退出？'),
          content: const Text('有正在运行的进程，关闭窗口将终止它们。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                await windowManager.destroy(); // 销毁窗口
              },
              child: const Text('确定退出'),
            ),
          ],
        ),
      );
    } else {
      await windowManager.destroy();
    }
  }

  @override
  void onWindowResize() async {
    final size = await windowManager.getSize();
    await _prefs.setDouble('window_width', size.width);
    await _prefs.setDouble('window_height', size.height);
  }
}
