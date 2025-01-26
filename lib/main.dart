import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'process_service.dart';  // 修改导入语句
import 'dart:io' show Platform;  // 添加 Platform 支持
import 'package:window_manager/window_manager.dart';  // 添加 window_manager 支持

void main() async {  // 修改为 async 函数
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
      // 禁止默认的关闭行为
      await windowManager.setPreventClose(true);
    });
  }
  
  // 读取保存的窗口大小
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
      debugShowCheckedModeBanner: false,  // 添加这一行移除调试标志
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
  final List<ProcessInfo> processes = [
    ProcessInfo(name: '新程序', path: '', args: ''),
  ];
  
  // 添加控制器
  final List<TextEditingController> _nameControllers = [];
  final List<TextEditingController> _pathControllers = [];
  final List<TextEditingController> _argsControllers = [];
  
  final ProcessService _processService = ProcessService();
  late SharedPreferences _prefs;

  @override
  void initState() {
    super.initState();
    
    // 添加窗口监听
    windowManager.addListener(this);
    
    // 初始化 SharedPreferences
    SharedPreferences.getInstance().then((prefs) {
      _prefs = prefs;
      
      // 加载已保存的进程数量
      final count = _prefs.getInt('process_count') ?? 1;
      
      setState(() {
        // 清空现有列表
        processes.clear();
        _nameControllers.clear();
        _pathControllers.clear();
        _argsControllers.clear();
        
        // 加载所有保存的进程
        for (var i = 0; i < count; i++) {
          final name = _prefs.getString('process_${i}_name') ?? '新程序';
          final path = _prefs.getString('process_${i}_path') ?? '';
          final args = _prefs.getString('process_${i}_args') ?? '';
          
          // 添加进程
          processes.add(ProcessInfo(name: name, path: path, args: args));
          
          // 添加对应的控制器
          _nameControllers.add(TextEditingController(text: name));
          _pathControllers.add(TextEditingController(text: path));
          _argsControllers.add(TextEditingController(text: args));
          
          // 添加状态监听
          processes.last.addListener(() {
            setState(() {});
          });
        }
      });
    });
  }

  // 添加 _saveSettings 方法
  Future<void> _saveSettings(int index) async {
    await _prefs.setString('process_${index}_name', processes[index].name);
    await _prefs.setString('process_${index}_path', processes[index].path);
    await _prefs.setString('process_${index}_args', processes[index].args);
    await _prefs.setInt('process_count', processes.length);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);  // 移除监听
    // 终止所有运行中的进程
    for (var process in processes) {
      if (process.isRunning) {
        _processService.stopProcess(process);
      }
    }
    
    // 释放所有控制器
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
        // 使用公共方法检查运行状态
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
                  // 停止所有运行中的进程
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
        ) ?? false;

        return shouldExit;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('进程管理器'),
          actions: [
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () {
                setState(() {
                  processes.add(ProcessInfo(name: '新程序', path: '', args: ''));
                  // 为新进程添加控制器
                  _nameControllers.add(TextEditingController(text: '新程序'));
                  _pathControllers.add(TextEditingController(text: ''));
                  _argsControllers.add(TextEditingController(text: ''));
                  // 添加监听器
                  processes.last.addListener(() {
                    setState(() {});
                  });
                  // 保存设置
                  _saveSettings(processes.length - 1);
                });
              },
            ),
          ],
        ),
        body: SingleChildScrollView(  // 添加整体滚动支持
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: List.generate(
                processes.length,
                (index) {
                  final process = processes[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8.0),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: IntrinsicHeight(  // 确保左右两栏高度一致
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 左侧配置栏 - 固定宽度
                            SizedBox(
                              width: 400,  // 固定左侧宽度
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          decoration: const InputDecoration(labelText: '程序名称'),
                                          controller: _nameControllers[index],
                                          onChanged: (value) {
                                            process.name = value;
                                            _saveSettings(index);
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: process.isRunning ? Colors.red : Colors.green,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(5),
                                          ),
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
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text(e.toString()),
                                                  backgroundColor: Colors.red,
                                                ),
                                              );
                                            }
                                          }
                                        },
                                        child: Text(process.isRunning ? '停止' : '启动'),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete, color: Colors.red),
                                        onPressed: () {
                                          if (process.isRunning) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('请先停止进程再删除'),
                                                backgroundColor: Colors.red,
                                              ),
                                            );
                                            return;
                                          }
                                          setState(() {
                                            // 移除控制器
                                            _nameControllers[index].dispose();
                                            _pathControllers[index].dispose();
                                            _argsControllers[index].dispose();
                                            _nameControllers.removeAt(index);
                                            _pathControllers.removeAt(index);
                                            _argsControllers.removeAt(index);
                                            // 移除进程
                                            process.removeListener(() {});
                                            processes.removeAt(index);
                                            // 重新保存所有设置
                                            for (var i = 0; i < processes.length; i++) {
                                              _saveSettings(i);
                                            }
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                  TextField(
                                    decoration: const InputDecoration(labelText: '程序路径'),
                                    controller: _pathControllers[index],
                                    onChanged: (value) {
                                      process.path = value;
                                      _saveSettings(index);
                                    },
                                  ),
                                  TextField(
                                    decoration: const InputDecoration(labelText: '程序参数'),
                                    controller: _argsControllers[index],
                                    onChanged: (value) {
                                      process.args = value;
                                      _saveSettings(index);
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '状态: ${process.isRunning ? "运行中" : "已停止"}',
                                    style: TextStyle(
                                      color: process.isRunning ? Colors.green : Colors.red,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // 分隔线
                            const VerticalDivider(thickness: 1),
                            // 右侧日志栏 - 自适应宽度
                            Expanded(
                              flex: 1,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('输出日志',
                                        style: TextStyle(fontWeight: FontWeight.bold)
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          process.clearOutput();
                                        },
                                        child: const Text('清除'),
                                      ),
                                    ],
                                  ),
                                  Container(
                                    height: 150,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[200],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    padding: const EdgeInsets.all(8),
                                    child: SingleChildScrollView(
                                      reverse: true,
                                      child: Text(
                                        process.output.isEmpty ? '暂无输出' : process.getRecentOutput(100),
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
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

  // 处理窗口关闭事件
  @override
  Future<void> onWindowClose() async {
    bool hasRunningProcess = processes.any((p) => p.isRunning);
    if (!hasRunningProcess) {
      await windowManager.destroy();
      return;
    }

    bool isPreventClose = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        title: const Text('确认退出'),
        content: const Text('退出程序将停止所有正在运行的进程，确定要退出吗？'),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              // 停止所有运行中的进程
              for (var process in processes) {
                if (process.isRunning) {
                  await _processService.stopProcess(process);
                }
              }
              Navigator.of(context).pop(false);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('退出'),
          ),
        ],
      ),
    ) ?? true;

    if (!isPreventClose) {
      await windowManager.destroy();
    }
  }
}