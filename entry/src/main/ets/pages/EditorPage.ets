// EditorPage.ets
import router from '@ohos.router';
import { FrameData } from '../model/FrameData';
import { FrameList } from '../components/FrameList';
import { Preview } from '../components/Preview';
import { ControlBar } from '../components/ControlBar';
import { ImageUtils } from '../common/ImageUtils';
import { TempFileManager } from '../common/TempFileManager';
import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ProjectManager, ProjectMeta } from '../common/ProjectManager';
import { ZapUtils } from '../common/ZapUtils';
import { ComposeTitleBar, promptAction } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { executeCommand, stopCommand, executeCommandSync, CommandSyncResult } from '@tyousan/ffmpeg';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import window from '@ohos.window';
import { showAbout } from '../common/ShowAbout';

// ====== 类型定义 ======

interface TargetSize {
  width: number;
  height: number;
}

interface FpsRepeat {
  targetFps: number;
  repeat: number;
}

// ====== 自定义对话框（不含新建项目对话框） ======
@CustomDialog
struct PropertiesDialog {
  controller?: CustomDialogController;
  onConfirm?: (fps: number, ratio: number) => void;

  private optionsFps: SelectOption[] = [
    { value: '默认(10 FPS)' },
    { value: '12 FPS' },
    { value: '6 FPS' }
  ];
  private optionsRatio: SelectOption[] = [
    { value: '横屏' },
    { value: '竖屏' },
    { value: '1:1' }
  ];

  paramFPS: number = 0;
  paramRatio: number = 0;

  @State selectedIndexFPS: number = 0;
  @State selectedTextFPS: string = this.optionsFps[0].value.toString();
  @State selectedIndexRatio: number = 0;
  @State selectedTextRatio: string = this.optionsRatio[0].value.toString();
  @State enabledRatio: boolean = false;

  aboutToAppear(): void {
    if (this.paramFPS === 12) {
      this.selectedIndexFPS = 1;
      this.selectedTextFPS = this.optionsFps[1].value.toString();
    } else if (this.paramFPS === 6) {
      this.selectedIndexFPS = 2;
      this.selectedTextFPS = this.optionsFps[2].value.toString();
    } else {
      this.selectedIndexFPS = 0;
      this.selectedTextFPS = this.optionsFps[0].value.toString();
    }

    if (this.paramRatio === 1) {
      this.selectedIndexRatio = 1;
      this.selectedTextRatio = this.optionsRatio[1].value.toString();
    } else if (this.paramRatio === 2) {
      this.selectedIndexRatio = 2;
      this.selectedTextRatio = this.optionsRatio[2].value.toString();
    } else {
      this.selectedIndexRatio = 0;
      this.selectedTextRatio = this.optionsRatio[0].value.toString();
    }
  }

  getSelectedFPS(): number {
    const value = this.optionsFps[this.selectedIndexFPS].value;
    if (value === this.optionsFps[1].value.toString()) return 12;
    if (value === this.optionsFps[2].value.toString()) return 6;
    return 10;
  }

  getSelectedRatio(): number {
    const value = this.optionsRatio[this.selectedIndexRatio].value;
    if (value === this.optionsRatio[1].value.toString()) return 1;
    if (value === this.optionsRatio[2].value.toString()) return 2;
    return 0;
  }

  build() {
    Column({ space: 20 }) {
      Text('属性')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)

      Row({ space: 20 }) {
        Text('帧率:')
          .width(60)
        Select(this.optionsFps)
          .selected(this.selectedIndexFPS)
          .value(this.selectedTextFPS)
          .onSelect((index: number, value: string) => {
            this.selectedIndexFPS = index;
            this.selectedTextFPS = value;
          })
          .layoutWeight(1)
          .height(50)
      }
      .width('100%')

      Row({ space: 20 }) {
        Text('比例:')
          .width(60)
        Select(this.optionsRatio)
          .selected(this.selectedIndexRatio)
          .value(this.selectedTextRatio)
          .onSelect((index: number, value: string) => {
            this.selectedIndexRatio = index;
            this.selectedTextRatio = value;
          })
          .layoutWeight(1)
          .height(50)
          .enabled(this.enabledRatio)
      }
      .width('100%')

      Row({ space: 20 }) {
        Button('取消')
          .buttonStyle(ButtonStyleMode.NORMAL)
          .onClick(() => { this.controller?.close(); })
          .layoutWeight(1)
        Button('确定')
          .onClick(() => {
            this.onConfirm?.(this.getSelectedFPS(), this.getSelectedRatio());
            this.controller?.close();
          })
          .layoutWeight(1)
      }
    }
    .padding(20)
  }
}

@CustomDialog
struct LoadingDialog {
  controller?: CustomDialogController;
  @State message: string = '保存中...';

  build() {
    Column() {
      Row() {
        LoadingProgress()
          .width(40)
          .height(40)
        Text(this.message)
          .fontSize(16)
          .margin({ left: 12 })
      }
      .padding(20)
    }
    .borderRadius(12)
    .backgroundColor($r('sys.color.background_tertiary'))
  }
}

@CustomDialog
struct ExportProgressDialog {
  controller?: CustomDialogController;
  onCancel?: () => void;

  build() {
    Column({ space: 16 }) {
      LoadingProgress()
        .width(48)
        .height(48)
      Text('导出中...')
        .fontSize(16)
        .fontColor($r('sys.color.font_primary'))
      Button('取消')
        .onClick(() => {
          this.onCancel?.();
          this.controller?.close();
        })
        .width(120)
        .buttonStyle(ButtonStyleMode.TEXTUAL)
    }
    .padding(24)
    .borderRadius(12)
    .backgroundColor($r('sys.color.background_tertiary'))
  }
}

// ====== 主页面 ======
@Entry
@Component
struct EditorPage {
  private loadingDialogController: CustomDialogController | null = null;
  private isSaving: boolean = false;
  private propertyDialogController: CustomDialogController | null = null;

  @State projectId: string = '';
  @State projectName: string = '';
  private isNewProject: boolean = true;

  @State frames: FrameData[] = [];
  @State currentIndex: number = -1;
  @State isPlaying: boolean = false;
  @State timerId: number = -1;
  @State fps: number = 10;
  @State ratio: number = 0;
  @State previewUri: string = '';
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;

  @State frameInterval: number = 1000 / 10;

  private isExporting: boolean = false;
  private exportCancelFlag: boolean = false;
  private exportDialogController: CustomDialogController | null = null;
  private currentExportSessionId: number = -1;   // 用于取消 FFmpeg 任务

  // ====== 屏幕适配 ======
  @State private isWideScreen: boolean = false;
  private windowObj: window.Window | null = null;
  private windowSizeCallback: () => void = () => {};

  // ====== 生命周期 ======
  async aboutToAppear() {
    // 初始化必要工具
    TempFileManager.init(this.context);
    ProjectManager.init(this.context);
    ZapUtils.init(this.context);

    // 清理历史导出的残留缓存（位于 cacheDir）
    try {
      const oldCache = this.context.cacheDir + '/ffmpeg_frames/';
      if (fileIo.accessSync(oldCache)) {
        this.deleteDirectoryRecursive(oldCache);
      }
    } catch (e) {}

    const params = router.getParams() as Record<string, string>;
    if (params && params['projectId']) {
      this.projectId = params['projectId'];
      this.isNewProject = false;
      this.loadProject();
    } else if (params && params['projectName']) {
      this.projectName = params['projectName'];
      this.projectId = Date.now().toString(36) + Math.random().toString(36).substring(2, 8);
      this.isNewProject = true;
    } else {
      router.back();
      return;
    }

    this.currentIndex = -1;
    this.updatePreview();

    // 窗口大小监听
    try {
      this.windowObj = await window.getLastWindow(this.context);
      this.updateScreenState();
      this.windowSizeCallback = () => {
        this.updateScreenState();
      };
      this.windowObj.on('windowSizeChange', this.windowSizeCallback);
    } catch (err) {
      console.error('获取窗口失败:', err);
    }
  }

  aboutToDisappear() {
    if (this.windowObj) {
      this.windowObj.off('windowSizeChange', this.windowSizeCallback);
    }
    // 清理编辑器帧缓存
    TempFileManager.clearEditorFrames();
  }

  private updateScreenState() {
    if (!this.windowObj) return;
    const rect = this.windowObj.getWindowProperties().windowRect;
    const widthVP = px2vp(rect.width);
    const heightVP = px2vp(rect.height);
    const isLandscape = widthVP > heightVP;
    this.isWideScreen = isLandscape && widthVP >= 600;
  }

  // ====== 基础方法 ======
  updatePreview(): void {
    this.previewUri = (this.currentIndex >= 0 && this.currentIndex < this.frames.length)
      ? this.frames[this.currentIndex].uri
      : '';
  }

  getTargetSize(): TargetSize {
    if (this.ratio === 1) return { width: 720, height: 1280 };
    if (this.ratio === 2) return { width: 1280, height: 1280 };
    return { width: 1280, height: 720 };
  }

  async addFrames(): Promise<void> {
    try {
      const options = new picker.PhotoSelectOptions();
      options.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 10;
      const photoPicker = new picker.PhotoViewPicker(this.context);
      const result = await photoPicker.select(options);
      if (result?.photoUris?.length) {
        const target = this.getTargetSize();
        let failCount = 0;
        for (const uri of result.photoUris) {
          const tempUri = await ImageUtils.loadAndSaveTemp(
            uri,
            target.width,
            target.height,
            this.frames.length
          );
          if (tempUri) {
            const id = Date.now().toString(36) + Math.random().toString(36).substring(2, 8);
            this.frames.push({ id, uri: tempUri });
          } else {
            failCount++;
          }
        }
        this.frames = [...this.frames];
        if (this.frames.length) {
          this.currentIndex = this.frames.length - 1;
          this.previewUri = this.frames[this.currentIndex].uri;
        }
        if (failCount > 0) {
          AlertDialog.show({
            title: '提示',
            message: `有 ${failCount} 张图片未能成功导入，可能是不支持的格式或尺寸。`,
            confirm: { value: '确定', action: () => {} }
          });
        }
      }
    } catch (err) {
      console.error('选择图片失败:', (err as BusinessError).message);
      AlertDialog.show({
        title: '错误',
        message: '选择图片过程中发生错误，请重试。',
        confirm: { value: '确定', action: () => {} }
      });
    }
  }

  moveFrame(from: number, to: number): void {
    if (from < 0 || to < 0 || from >= this.frames.length || to >= this.frames.length) return;
    const item = this.frames.splice(from, 1)[0];
    this.frames.splice(to, 0, item);
    this.frames = [...this.frames];
    this.currentIndex = to;
    this.updatePreview();
  }

  deleteFrame(index: number): void {
    if (index < 0 || index >= this.frames.length) return;
    this.frames.splice(index, 1);
    this.frames = [...this.frames];
    this.currentIndex = this.frames.length ? this.frames.length - 1 : -1;
    this.updatePreview();
  }

  togglePlay(): void {
    if (!this.frames.length) return;
    if (this.isPlaying) {
      this.isPlaying = false;
      if (this.timerId !== -1) {
        clearTimeout(this.timerId);
        this.timerId = -1;
      }
    } else {
      if (this.currentIndex < 0 || this.currentIndex >= this.frames.length - 1) {
        this.currentIndex = 0;
      }
      this.isPlaying = true;
      this.updatePreview();
      this.timerId = setTimeout(() => this.playNextFrame(), this.frameInterval);
    }
  }

  playNextFrame(): void {
    if (!this.isPlaying) return;
    const next = this.currentIndex + 1;
    if (next >= this.frames.length) {
      this.isPlaying = false;
      if (this.timerId !== -1) {
        clearTimeout(this.timerId);
        this.timerId = -1;
      }
      return;
    }
    this.currentIndex = next;
    this.updatePreview();
    this.timerId = setTimeout(() => this.playNextFrame(), this.frameInterval);
  }

  onProgressChange(pos: number): void {
    if (!this.isPlaying && pos >= 0 && pos < this.frames.length) {
      this.currentIndex = pos;
      this.updatePreview();
    }
  }

  showPropertyDialog(): void {
    if (this.propertyDialogController) {
      this.propertyDialogController.close();
      this.propertyDialogController = null;
    }
    this.propertyDialogController = new CustomDialogController({
      builder: PropertiesDialog({
        paramFPS: this.fps,
        paramRatio: this.ratio,
        enabledRatio: (this.frames.length === 0),
        onConfirm: (newFPS: number, newRatio: number) => {
          this.fps = newFPS;
          this.frameInterval = 1000 / newFPS;
          this.ratio = newRatio;
        }
      })
    });
    this.propertyDialogController.open();
  }

  async loadProject() {
    const projects = await ProjectManager.getProjects();
    const meta = projects.find(p => p.id === this.projectId);
    if (!meta) return;
    this.projectName = meta.name;
    const result = await ZapUtils.loadZap(meta.filePath);
    if (result) {
      this.frames = result.frames;
      this.fps = result.fps;
      this.ratio = result.ratioIndex;
      this.frameInterval = 1000 / this.fps;
      this.currentIndex = this.frames.length > 0 ? this.frames.length - 1 : -1;
      this.updatePreview();
    }
  }

  onBackPress() {
    this.handleBack();
    return true;
  }

  async saveProject() {
    if (this.frames.length === 0) {
      if (this.isNewProject) {
        await ProjectManager.deleteProject(this.projectId);
      }
      return;
    }

    const fileName = `${this.projectId}.zhuziani`;
    const filePath = this.context.filesDir + '/' + fileName;
    const success = await ZapUtils.saveZap(filePath, this.frames, this.fps, this.ratio);
    if (success) {
      const meta: ProjectMeta = {
        id: this.projectId,
        name: this.projectName,
        filePath: filePath,
        lastModified: Date.now(),
        frameCount: this.frames.length,
      };
      await ProjectManager.upsertProject(meta);
      this.isNewProject = false;
    }
  }

  async handleBack() {
    if (this.isSaving) return;
    this.isSaving = true;

    if (this.loadingDialogController) {
      this.loadingDialogController.close();
      this.loadingDialogController = null;
    }
    this.loadingDialogController = new CustomDialogController({
      builder: LoadingDialog({ message: '保存中...' }),
      autoCancel: false,
      customStyle: true,
    });
    this.loadingDialogController.open();

    try {
      await this.saveProject();
    } catch (e) {
      console.error('保存失败:', e);
    } finally {
      if (this.loadingDialogController) {
        this.loadingDialogController.close();
        this.loadingDialogController = null;
      }
      this.isSaving = false;
      router.back();
    }
  }

  // ========================================================
  // ==================== 导出功能 ===========================
  // ========================================================

  private getTargetFpsAndRepeat(): FpsRepeat {
    if (this.fps === 6) return { targetFps: 12, repeat: 2 };
    if (this.fps === 10) return { targetFps: 30, repeat: 3 };
    return { targetFps: this.fps, repeat: 1 };
  }

  private async loadPixelMapFromUri(uri: string): Promise<image.PixelMap | null> {
    try {
      const filePath = uri.startsWith('file://') ? uri.substring(7) : uri;
      const file = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(file.fd);
      const buffer = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, buffer);
      fileIo.closeSync(file);
      const imageSource = image.createImageSource(buffer);
      return await imageSource.createPixelMap();
    } catch (e) {
      console.error('loadPixelMapFromUri失败', e);
      return null;
    }
  }

  // ====== 保存视频到相册（弹窗授权方式） ======
  private async saveVideoToGallery(filePath: string): Promise<void> {
    try {
      fileIo.statSync(filePath);
    } catch {
      throw new Error(`视频文件不存在: ${filePath}`);
    }

    const phHelper = photoAccessHelper.getPhotoAccessHelper(this.context);
    const timestamp = Date.now();
    const configs: photoAccessHelper.PhotoCreationConfig[] = [
      {
        title: `Zhuzi_${timestamp}`,
        fileNameExtension: 'mp4',
        photoType: photoAccessHelper.PhotoType.VIDEO,
        subtype: photoAccessHelper.PhotoSubtype.DEFAULT,
      }
    ];

    let destUris: string[];
    try {
      destUris = await phHelper.showAssetsCreationDialog([filePath], configs);
    } catch (err) {
      if (err.code === 202) {
        throw new Error('用户取消保存');
      }
      throw new Error(`弹窗授权失败: ${err.message || String(err)}`);
    }

    if (!destUris || destUris.length === 0) {
      throw new Error('用户取消保存');
    }

    const destUri = destUris[0];
    const srcFile = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
    const destFile = fileIo.openSync(destUri, fileIo.OpenMode.WRITE_ONLY);
    fileIo.copyFileSync(srcFile.fd, destFile.fd);
    fileIo.closeSync(srcFile);
    fileIo.closeSync(destFile);
  }

  async startExport() {
    if (this.frames.length < 2) {
      promptAction.showToast({ message: '至少需要2帧才能导出视频' });
      return;
    }
    if (this.isExporting) return;

    this.exportCancelFlag = false;
    this.isExporting = true;
    this.currentExportSessionId = -1;

    this.exportDialogController = new CustomDialogController({
      builder: ExportProgressDialog({
        onCancel: () => {
          this.exportCancelFlag = true;
          // 如果 FFmpeg 正在运行，立即停止
          if (this.currentExportSessionId > 0) {
            stopCommand({ sessionId: this.currentExportSessionId });
          }
        }
      }),
      autoCancel: false,
      customStyle: true,
    });
    this.exportDialogController.open();

    try {
      await this.doExport();
      promptAction.showToast({ message: '视频已保存到相册' });
    } catch (e) {
      // 安全获取错误信息
      const errorMessage = e instanceof Error ? e.message : String(e);
      if (errorMessage.includes('取消') || errorMessage === 'Cancelled') {
        promptAction.showToast({ message: '已取消保存' });
      } else {
        console.error('导出失败:', e);
        promptAction.showToast({ message: `导出失败: ${errorMessage || '未知错误'}` });
      }
    } finally {
      this.isExporting = false;
      if (this.exportDialogController) {
        this.exportDialogController.close();
        this.exportDialogController = null;
      }
    }
  }

  private async doExport(): Promise<void> {
    const fpsRepeat = this.getTargetFpsAndRepeat();
    const targetFps = fpsRepeat.targetFps;

    const tempDir = this.context.cacheDir + '/export/frames/';
    const outputPath = this.context.cacheDir + '/export/export_video.mp4';

    // 创建临时目录
    try {
      if (fileIo.accessSync(tempDir)) {
        this.deleteDirectoryRecursive(tempDir);
      }
      fileIo.mkdirSync(tempDir, true);
    } catch (e) {
      console.warn('临时目录创建:', e);
    }

    // 导出帧 – 每帧重复 repeat 次
    let frameIndex = 1; // 序号从1开始
    for (let i = 0; i < this.frames.length; i++) {
      if (this.exportCancelFlag) {
        this.deleteDirectoryRecursive(tempDir);
        throw new Error('导出取消');
      }
      const pixelMap = await this.loadPixelMapFromUri(this.frames[i].uri);
      if (!pixelMap) continue;

      const imagePacker = image.createImagePacker();
      const packOpts: image.PackingOption = {
        format: 'image/png',
        quality: 100,
      };
      const pngData = await imagePacker.packing(pixelMap, packOpts);
      pixelMap.release();

      // 重复写入 repeat 次
      for (let rep = 0; rep < fpsRepeat.repeat; rep++) {
        const fileName = `frame_${String(frameIndex).padStart(5, '0')}.png`;
        const filePath = tempDir + fileName;
        const file = fileIo.openSync(filePath,
          fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC
        );
        fileIo.writeSync(file.fd, pngData);
        fileIo.closeSync(file);
        frameIndex++;
      }
    }

    if (this.exportCancelFlag) {
      this.deleteDirectoryRecursive(tempDir);
      throw new Error('导出取消');
    }

    const pattern = tempDir + 'frame_%05d.png';
    const commandArgs = [
      '-framerate', targetFps.toString(),
      '-i', pattern,
      '-c:v', 'libx264',
      '-pix_fmt', 'yuv420p',
      '-y',
      outputPath
    ];
    const commandString = commandArgs.join(' ');
    console.info(`FFmpeg 命令: ${commandString}`);

    // 改为异步 executeCommand
    try {
      await new Promise<void>((resolve, reject) => {
        executeCommand({
          cmd: commandString,
          start: (result) => {
            this.currentExportSessionId = result.sessionId;
            console.info('FFmpeg 导出任务启动, sessionId:', this.currentExportSessionId);
          },
          success: () => {
            console.info('FFmpeg 导出成功');
            resolve();
          },
          fail: (error) => {
            console.error('FFmpeg 导出失败:', error);
            reject(new Error(error.message || 'FFmpeg 执行失败'));
          },
          cancel: () => {
            console.info('FFmpeg 导出被取消');
            reject(new Error('Cancelled'));
          },
          complete: () => {
            this.currentExportSessionId = -1;
          }
        });
      });
    } catch (err) {
      // 清理临时目录和输出文件
      this.deleteDirectoryRecursive(tempDir);
      try { fileIo.unlinkSync(outputPath); } catch {}
      // 确保抛出 Error 类型
      throw new Error(err instanceof Error ? err.message : String(err));
    }

    // 清理临时帧目录
    this.deleteDirectoryRecursive(tempDir);

    // 检查是否被取消（可能在 FFmpeg 执行期间取消）
    if (this.exportCancelFlag) {
      try { fileIo.unlinkSync(outputPath); } catch {}
      throw new Error('导出取消');
    }

    // 保存到相册
    await this.saveVideoToGallery(outputPath);
    try { fileIo.unlinkSync(outputPath); } catch {}
  }

  private deleteDirectoryRecursive(path: string): void {
    try {
      const files = fileIo.listFileSync(path);
      for (const file of files) {
        const fullPath = `${path}/${file}`;
        const stat = fileIo.statSync(fullPath);
        if (stat.isDirectory()) {
          this.deleteDirectoryRecursive(fullPath);
        } else {
          fileIo.unlinkSync(fullPath);
        }
      }
      fileIo.rmdirSync(path);
    } catch (e) {
      console.warn('删除目录失败:', path, e);
    }
  }

  // ========================================================
  // ====================== UI 构建 =========================
  // ========================================================

  @Builder
  buildTopBar() {
    Row() {
      Button() {
        SymbolGlyph($r('sys.symbol.arrow_left'))
          .fontSize(24)
          .width(24)
          .height(24)
          .fontColor([$r('sys.color.font_primary')])
      }
      .onClick(() => {
        this.handleBack();
      })
      .height(40)
      .width(40)
      .buttonStyle(ButtonStyleMode.TEXTUAL)

      Text('编辑器')
        .layoutWeight(1)
        .fontSize(18)
        .fontColor($r('sys.color.font_primary'))
        .fontWeight(FontWeight.Medium)
        .textAlign(TextAlign.Center)

      Button() {
        SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
          .fontSize(24)
          .width(24).height(24)
          .fontColor([$r('sys.color.font_primary')])

      }
      .buttonStyle(ButtonStyleMode.TEXTUAL)
      .bindMenu([
        { value: '属性', action: () => this.showPropertyDialog() },
        { value: '导出', action: () => this.startExport() },
        { value: '关于', action: () => showAbout() }
      ])
      .width(40)
      .height(40)
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .backgroundColor($r('sys.color.background_primary'))
    .shadow({ radius: 2, color: '#1A000000', offsetY: 1 })

  }

  build() {
    Column() {
      this.buildTopBar();

      if (this.isWideScreen) {
        Row() {
          FrameList({
            frames: this.frames,
            currentIndex: this.currentIndex,
            onSelect: (idx: number) => {
              this.currentIndex = idx;
              this.updatePreview();
            },
            onMove: (from: number, to: number) => this.moveFrame(from, to),
            onDelete: (idx: number) => this.deleteFrame(idx),
            onAdd: () => this.addFrames()
          })
            .width(300)
            .height('100%');

          Column() {
            Preview({ imageUri: this.previewUri })
              .layoutWeight(1);
            ControlBar({
              isPlaying: this.isPlaying,
              progress: this.currentIndex,
              max: this.frames.length - 1,
              onPlayToggle: () => this.togglePlay(),
              onProgressChange: (pos: number) => this.onProgressChange(pos)
            })
              .height(80);
          }
          .layoutWeight(1)
          .height('100%');
        }
        .layoutWeight(1);
      } else {
        Column() {
          Column() {
            Preview({ imageUri: this.previewUri })
              .layoutWeight(1);
            ControlBar({
              isPlaying: this.isPlaying,
              progress: this.currentIndex,
              max: this.frames.length - 1,
              onPlayToggle: () => this.togglePlay(),
              onProgressChange: (pos: number) => this.onProgressChange(pos)
            })
              .height(80);
          }
          .layoutWeight(1)
          .width('100%');

          FrameList({
            frames: this.frames,
            currentIndex: this.currentIndex,
            onSelect: (idx: number) => {
              this.currentIndex = idx;
              this.updatePreview();
            },
            onMove: (from: number, to: number) => this.moveFrame(from, to),
            onDelete: (idx: number) => this.deleteFrame(idx),
            onAdd: () => this.addFrames()
          })
            .height('50%')
            .width('100%');
        }
        .layoutWeight(1);
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_tertiary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}