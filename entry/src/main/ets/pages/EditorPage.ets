import router from '@ohos.router';
import { FrameData } from '../model/FrameData';
import { FrameList } from '../components/FrameList';
import { Preview } from '../components/Preview';
import { ControlBar } from '../components/ControlBar';
import { ImageUtils } from '../common/ImageUtils';
import { TempFileManager } from '../common/TempFileManager';
import { picker } from '@kit.CoreFileKit';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ProjectManager, ProjectMeta } from '../common/ProjectManager';
import { ZapUtils } from '../common/ZapUtils';
import { promptAction } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
// ====== 使用 @tyousan/ffmpeg ======
import { executeCommandSync, CommandSyncResult } from '@tyousan/ffmpeg';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { dataSharePredicates } from '@kit.ArkData';

// ====== 类型定义 ======
interface TargetSize {
  width: number;
  height: number;
}

interface FpsRepeat {
  targetFps: number;
  repeat: number;
}

// ====== 自定义对话框 ======
@CustomDialog
struct NewProjectDialog {
  controller: CustomDialogController;
  onConfirm: (name: string) => void = () => {};

  @State inputText: string = '';

  build() {
    Column({ space: 16 }) {
      Text('新项目')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)

      TextInput({ placeholder: '请输入项目名称', text: this.inputText })
        .width('80%')
        .onChange((value: string) => {
          this.inputText = value;
        })

      Row({ space: 20 }) {
        Button('取消')
          .onClick(() => {
            this.controller.close();
          })
        Button('创建')
          .type(ButtonType.Normal)
          .backgroundColor('#007AFF')
          .fontColor(Color.White)
          .onClick(() => {
            if (this.inputText.trim()) {
              this.onConfirm(this.inputText.trim());
              this.controller.close();
            }
          })
      }
    }
    .padding(24)
    .backgroundColor(Color.White)
    .borderRadius(12)
  }
}

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
          .width('70%')
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
          .width('70%')
          .height(50)
          .enabled(this.enabledRatio)
      }
      .width('100%')

      Row({ space: 20 }) {
        Button('取消')
          .buttonStyle(ButtonStyleMode.NORMAL)
          .onClick(() => { this.controller?.close(); })
          .width(128)
        Button('确定')
          .onClick(() => {
            this.onConfirm?.(this.getSelectedFPS(), this.getSelectedRatio());
            this.controller?.close();
          })
          .width(128)
      }
    }
    .padding(20)
  }
}

@CustomDialog
struct LoadingDialog {
  controller: CustomDialogController;
  @State message: string = '保存中...';

  build() {
    Column() {
      Row() {
        LoadingProgress()
          .width(40)
          .height(40)
          .color('#007AFF')
        Text(this.message)
          .fontSize(16)
          .margin({ left: 12 })
      }
      .padding(20)
    }
    .backgroundColor(Color.White)
    .borderRadius(12)
  }
}

@CustomDialog
struct ExportProgressDialog {
  controller: CustomDialogController;
  onCancel?: () => void;

  build() {
    Column({ space: 16 }) {
      LoadingProgress()
        .width(48)
        .height(48)
        .color('#007AFF')
      Text('导出中...')
        .fontSize(16)
        .fontColor(Color.Black)
      Button('取消')
        .onClick(() => {
          this.onCancel?.();
          this.controller.close();
        })
        .width(120)
        .buttonStyle(ButtonStyleMode.NORMAL)
    }
    .padding(24)
    .backgroundColor(Color.White)
    .borderRadius(12)
  }
}

@Entry
@Component
struct EditorPage {
  private loadingDialogController: CustomDialogController | null = null;
  private isSaving: boolean = false;
  private propertyDialogController: CustomDialogController | null = null;
  private newProjectDialogController: CustomDialogController | null = null;

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

  // ====== 生命周期 ======
  aboutToAppear() {
    const params = router.getParams() as Record<string, string>;
    if (params && params['projectId']) {
      this.projectId = params['projectId'];
      this.isNewProject = false;
      this.loadProject();
    } else {
      this.showNewProjectDialog();
    }
    TempFileManager.init(this.context);
    this.currentIndex = -1;
    this.updatePreview();
  }

  aboutToDisappear() {
    this.saveProject();
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

  showAbout(): void {
    AlertDialog.show({
      title: '关于',
      message: '竹子定格动画\\nHarmonyOS NEXT 版本\\n\\n本程序基于 GPLv3 许可证开源。\\n使用的 FFmpeg 库遵循 GPLv3 许可证。\\n源代码可在 https://github.com/Zhuziexe/ZhuziAnimation_HMOS 获取。',
      confirm: { value: '确定', action: () => {} }
    });
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

  showNewProjectDialog() {
    if (this.newProjectDialogController) {
      this.newProjectDialogController.close();
      this.newProjectDialogController = null;
    }
    this.newProjectDialogController = new CustomDialogController({
      builder: NewProjectDialog({
        onConfirm: (name: string) => {
          this.projectName = name;
          this.projectId = Date.now().toString(36) + Math.random().toString(36).substring(2, 8);
          this.isNewProject = true;
        }
      })
    });
    this.newProjectDialogController.open();
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

    const fileName = `${this.projectId}.zap`;
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

  // ====== 保存视频到相册（MediaAssetChangeRequest 方式） ======
  private async saveVideoToGallery(filePath: string): Promise<void> {
    const phHelper = photoAccessHelper.getPhotoAccessHelper(this.context);
    // 1. 创建空视频资产，获得 URI
    const assetUri = await phHelper.createAsset(photoAccessHelper.PhotoType.VIDEO, 'mp4');

    // 2. 获取所有资产，找到刚创建的资产
    const predicates = new dataSharePredicates.DataSharePredicates();
    const fetchOptions: photoAccessHelper.FetchOptions = {
      fetchColumns: [],
      predicates: predicates
    };
    const fetchResult = await phHelper.getAssets(fetchOptions);
    const allAssets = await fetchResult.getAllObjects();
    const targetAsset = allAssets.find(asset => asset.uri === assetUri);
    if (!targetAsset) {
      throw new Error('无法找到刚创建的资产');
    }

    // 3. 使用 MediaAssetChangeRequest 添加视频资源
    const assetChangeRequest = new photoAccessHelper.MediaAssetChangeRequest(targetAsset);
    assetChangeRequest.addResource(photoAccessHelper.ResourceType.VIDEO_RESOURCE, 'file://' + filePath);
    await phHelper.applyChanges(assetChangeRequest);
  }

  async startExport() {
    if (this.frames.length < 2) {
      promptAction.showToast({ message: '至少需要2帧才能导出视频' });
      return;
    }
    if (this.isExporting) return;

    const atManager = abilityAccessCtrl.createAtManager();
    const permissions: Array<Permissions> = [
      'ohos.permission.WRITE_IMAGEVIDEO',
      'ohos.permission.READ_IMAGEVIDEO'
    ];
    try {
      await atManager.requestPermissionsFromUser(this.context, permissions);
    } catch (err) {
      promptAction.showToast({ message: '需要相册权限才能导出' });
      return;
    }

    this.exportCancelFlag = false;
    this.isExporting = true;

    this.exportDialogController = new CustomDialogController({
      builder: ExportProgressDialog({
        onCancel: () => {
          this.exportCancelFlag = true;
        }
      }),
      autoCancel: false,
      customStyle: true,
    });
    this.exportDialogController.open();

    try {
      await this.doExport();
    } catch (e) {
      if (e instanceof Error && e.message === '导出取消') {
        promptAction.showToast({ message: '已取消导出' });
      } else {
        console.error('导出失败', e);
        promptAction.showToast({ message: '导出失败，请重试' });
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
    const repeat = fpsRepeat.repeat;

    // 创建临时目录并导出帧
    const tempDir = this.context.filesDir + '/ffmpeg_frames/';
    try {
      if (fileIo.accessSync(tempDir)) {
        this.deleteDirectoryRecursive(tempDir);
      }
      fileIo.mkdirSync(tempDir);
    } catch (e) {
      console.warn('临时目录创建:', e);
    }

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

      const fileName = `frame_${String(i + 1).padStart(5, '0')}.png`;
      const filePath = tempDir + fileName;
      const file = fileIo.openSync(filePath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC
      );
      fileIo.writeSync(file.fd, pngData);
      fileIo.closeSync(file);
    }

    if (this.exportCancelFlag) {
      this.deleteDirectoryRecursive(tempDir);
      throw new Error('导出取消');
    }

    const outputPath = `${this.context.filesDir}/export_${Date.now()}.mp4`;
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

    // ====== 使用 @tyousan/ffmpeg 的 executeCommandSync ======
    try {
      const result: CommandSyncResult = executeCommandSync(commandString);
      if (result.evenType !== 'onSuccess') {
        const errorMsg = result.failStackTrace || `错误码: ${result.errCode ?? '未知'}`;
        throw new Error(`FFmpeg 执行失败: ${errorMsg}`);
      }
      console.info('FFmpeg 执行成功');
    } catch (err) {
      console.error('FFmpeg 执行异常:', err);
      if (err instanceof Error) {
        throw err;
      } else {
        throw new Error(`FFmpeg 执行异常: ${String(err)}`);
      }
    }

    this.deleteDirectoryRecursive(tempDir);

    if (this.exportCancelFlag) {
      try { fileIo.unlinkSync(outputPath); } catch (e) {}
      throw new Error('导出取消');
    }

    // 保存到相册
    await this.saveVideoToGallery(outputPath);
    try { fileIo.unlinkSync(outputPath); } catch (e) {}

    promptAction.showToast({ message: '已保存到相册' });
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

  build() {
    Column() {
      Row() {
        Button() {
          SymbolGlyph($r('sys.symbol.arrow_left'))
            .fontSize(24)
            .width(24)
            .height(24)
        }
        .onClick(() => {
          this.handleBack();
        })
        .height(32)
        .width(32)
        .buttonStyle(ButtonStyleMode.TEXTUAL)

        Text('编辑器')
          .layoutWeight(1)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .textAlign(TextAlign.Center)

        Button() {
          Image($r('sys.media.ohos_ic_public_more'))
            .width(24).height(24)
        }
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .bindMenu([
          { value: '属性', action: () => this.showPropertyDialog() },
          { value: '导出', action: () => this.startExport() },
          { value: '关于', action: () => this.showAbout() }
        ])
        .width(32)
        .height(32)
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#FFFFFF')
      .shadow({ radius: 2, color: '#1A000000', offsetY: 1 })

      Row() {
        FrameList({
          frames: this.frames,
          currentIndex: this.currentIndex,
          onSelect: (idx: number) => { this.currentIndex = idx; this.updatePreview(); },
          onMove: (from: number, to: number) => this.moveFrame(from, to),
          onDelete: (idx: number) => this.deleteFrame(idx),
          onAdd: () => this.addFrames()
        })
          .width(300)
          .height('100%')

        Column() {
          Preview({ imageUri: this.previewUri })
            .layoutWeight(1)
          ControlBar({
            isPlaying: this.isPlaying,
            progress: this.currentIndex,
            max: this.frames.length - 1,
            onPlayToggle: () => this.togglePlay(),
            onProgressChange: (pos: number) => this.onProgressChange(pos)
          })
            .height(80)
        }
        .layoutWeight(1)
        .height('100%')
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}