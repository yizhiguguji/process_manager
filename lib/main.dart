import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'process_service.dart';  // 修改导入语句
import 'dart:io' show Platform;  // 添加 Platform 支持
import 'package:window_manager/window_manager.dart';  // 添加 window_manager 支持

void main() {
  WidgetsFlutterBinding.ensureInitialized();  // 确保Flutter绑定初始化
  
  // 读取保存的窗口大小
  SharedPreferences.getInstance().then((prefs) {
    final width = prefs.getDouble('window_width') ?? 800.0;
    final height = prefs.getDouble('window_height') ?? 600.0;
    
    if (Platform.isMacOS || Platform.isWindows) {
      WindowManager.instance.ensureInitialized();
      WindowManager.instance.setSize(Size(width, height));
    }
  });
  
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
  
  // 移除程序管理器相关的控制器
  final List<TextEditingController> _nameControllers = [];
  final List<TextEditingController> _pathControllers = [];
  final List<TextEditingController> _argsControllers = [];
  
  final ProcessService _processService = ProcessService();
  late SharedPreferences _prefs;

  @override
  void initState() {
    super.initState();
    // 初始化窗口管理器
    if (Platform.isMacOS || Platform.isWindows) {
      windowManager.addListener(this);
    }
    // 初始化控制器
    for (var process in processes) {
      _nameControllers.add(TextEditingController(text: process.name));
      _pathControllers.add(TextEditingController(text: process.path));
      _argsControllers.add(TextEditingController(text: process.args));
    }
    _loadSettings();
    // 添加监听器
    for (var process in processes) {
      process.addListener(() {
        setState(() {});
      });
    }
  }
  
  @override
  void dispose() {
    if (Platform.isMacOS || Platform.isWindows) {
      windowManager.removeListener(this);
    }
    // 释放其他控制器
    for (var controller in _nameControllers) {
      controller.dispose();
    }
    for (var controller in _pathControllers) {
      controller.dispose();
    }
    for (var controller in _argsControllers) {
      controller.dispose();
    }
    // 移除监听器
    for (var process in processes) {
      process.removeListener(() {});
    }
    super.dispose();
  }

  // 添加窗口大小变化处理方法
  @override
  void onWindowResize() async {
    final size = await windowManager.getSize();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('window_width', size.width);
    await prefs.setDouble('window_height', size.height);
  }

  Future<void> _loadSettings() async {
    _prefs = await SharedPreferences.getInstance();
    
    // 获取保存的进程数量
    final processCount = _prefs.getInt('process_count') ?? 1;
    
    setState(() {
      // 清空现有列表
      processes.clear();
      _nameControllers.clear();
      _pathControllers.clear();
      _argsControllers.clear();
      
      // 重新加载所有进程
      for (var i = 0; i < processCount; i++) {
        final name = _prefs.getString('process_${i}_name') ?? '新程序';
        final path = _prefs.getString('process_${i}_path') ?? '';
        final args = _prefs.getString('process_${i}_args') ?? '';
        
        // 添加进程
        processes.add(ProcessInfo(name: name, path: path, args: args));
        
        // 添加控制器
        _nameControllers.add(TextEditingController(text: name));
        _pathControllers.add(TextEditingController(text: path));
        _argsControllers.add(TextEditingController(text: args));
        
        // 添加监听器
        processes.last.addListener(() {
          setState(() {});
        });
      }
    });
  }

  // 修改 _saveSettings 方法
  Future<void> _saveSettings(int index) async {
    await _prefs.setString('process_${index}_name', processes[index].name);
    await _prefs.setString('process_${index}_path', processes[index].path);
    await _prefs.setString('process_${index}_args', processes[index].args);
    // 保存进程总数
    await _prefs.setInt('process_count', processes.length);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                                  height: 150,  // 固定高度
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
    );
  }
}