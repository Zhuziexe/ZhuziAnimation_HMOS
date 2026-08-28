export function showAbout(): void {
  AlertDialog.show({
    title: '关于',
    message: '竹子视频\n版本1.0.1\n\n本程序基于 GPLv3 许可证开源。\n使用的 FFMPEG 库遵循 GPLv3 许可证。\n源代码可在 https://github.com/Zhuziexe/ZhuziAnimation_HMOS 获取。',
    confirm: { value: '确定', action: () => {} }
  });
}