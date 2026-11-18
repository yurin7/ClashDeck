import 'package:material_ui/material_ui.dart';

import 'theme.dart';
import 'widgets/select_sheet.dart';
import 'widgets/selectable_tile.dart';

/// 概览页「导入」的两种来源。
enum ImportSource { paste, file }

/// 导入方式选择：粘贴文本 / 从文件选择。
///
/// 顶部「导入」按钮的语义不变，先让用户选来源再进入各自的流程。
Future<ImportSource?> showImportSourceSheet(BuildContext context) {
  return showSelectSheet<ImportSource>(
    context,
    title: '导入配置',
    subtitle: '粘贴文本，或从手机里选一份文件',
    body: (ctx) => ListView(
      padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
      children: [
        SelectableTile(
          leading: const Icon(Icons.notes_outlined, size: 20),
          title: const Text('粘贴文本'),
          subtitle: Text('分享链接、订阅地址或整份 YAML', style: hintStyle(ctx)),
          onTap: () => Navigator.pop(ctx, ImportSource.paste),
        ),
        SelectableTile(
          leading: const Icon(Icons.upload_file, size: 20),
          title: const Text('从文件选择'),
          subtitle: Text(
            '支持 .yaml / .yml / .txt，最大 2MB',
            style: hintStyle(ctx),
          ),
          onTap: () => Navigator.pop(ctx, ImportSource.file),
        ),
      ],
    ),
  );
}
