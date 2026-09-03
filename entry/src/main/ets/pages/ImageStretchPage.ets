import router from '@ohos.router';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { promptAction } from '@kit.ArkUI';
import { executeCommand, stopCommand, executeCommandSync, CommandSyncResult } from '@tyousan/ffmpeg';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ProcessingDialog } from '../components/ProcessingDialog';

// ---------- 接口定义 ----------
interface FfmpegResult {
  sessionId?: number;
}

interface FfmpegError {
  sessionId?: number;
  errCode?: number | string;
  message?: string;
  stderr?: string;
}

@Entry
@Component
struct ImageStretchPage {
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;

  // ---------- 图片数据 ----------
  @State imageUri: string = '';
  @State originalWidth: number = 0;
  @State originalHeight: number = 0;
  @State previewPath: string = '';
  @State isLoading: boolean = true;

  // ---------- 缩放参数 ----------
  @State targetWidth: string = '';
  @State targetHeight: string = '';
  @State isRatioLocked: boolean = true; // true=等比例, false=自由拉伸

  // ---------- 状态控制 ----------
  @State isExporting: boolean = false;
  private currentSessionId: number = -1;
  private cancelFlag: boolean = false;
  private isPageAlive: boolean = true;
  private progressDialogController: CustomDialogController | null = null;

  aboutToAppear() {
    const params = router.getParams() as Record<string, string>;
    if (params && params['imageUri']) {
      this.imageUri = params['imageUri'];
      this.prepareImage();
    } else {
      promptAction.showToast({ message: '未传入图片' });
      router.back();
    }
  }

  aboutToDisappear() {
    this.isPageAlive = false;
    if (this.progressDialogController) {
      try { this.progressDialogController.close(); } catch {}
      this.progressDialogController = null;
    }
    const cacheDir = this.context.cacheDir + '/tools/stretch/';
    try { fileIo.unlinkSync(cacheDir + 'source.png'); } catch {}
    try { fileIo.unlinkSync(cacheDir + 'stretched.png'); } catch {}
  }

  // ---------- 准备图片 ----------
  private async prepareImage() {
    try {
      this.isLoading = true;
      const cacheDir = this.context.cacheDir + '/tools/stretch/';
      try { fileIo.mkdirSync(cacheDir, true); } catch {}

      const destPath = cacheDir + 'source.png';
      await this.copyMediaUriToPath(this.imageUri, destPath);
      this.previewPath = destPath;

      const imgSource = image.createImageSource(destPath);
      const info = await imgSource.getImageInfo();
      this.originalWidth = info.size.width;
      this.originalHeight = info.size.height;

      // 默认目标尺寸 = 原图尺寸
      this.targetWidth = this.originalWidth.toString();
      this.targetHeight = this.originalHeight.toString();

      this.isLoading = false;
    } catch (err) {
      console.error('加载图片失败:', (err as BusinessError).message);
      promptAction.showToast({ message: '加载图片失败' });
      router.back();
    }
  }

  private async copyMediaUriToPath(mediaUri: string, destPath: string): Promise<void> {
    try { fileIo.unlinkSync(destPath); } catch {}
    const srcFd = fileIo.openSync(mediaUri, fileIo.OpenMode.READ_ONLY);
    if (srcFd.fd < 0) throw new Error('打开媒体失败');
    const destFd = fileIo.openSync(destPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      const bufferSize = 1024 * 1024;
      const buf = new ArrayBuffer(bufferSize);
      let readLen: number;
      while ((readLen = fileIo.readSync(srcFd.fd, buf)) > 0) {
        fileIo.writeSync(destFd.fd, buf, { length: readLen });
      }
    } finally {
      fileIo.closeSync(srcFd);
      fileIo.closeSync(destFd);
    }
  }

  // ---------- 核心逻辑：同步宽高 ----------
  private onWidthChange(value: string) {
    const w = parseInt(value);
    if (!isNaN(w) && w > 0 && this.isRatioLocked) {
      // 等比例锁定：根据宽度计算高度
      const h = Math.round(w * (this.originalHeight / this.originalWidth));
      this.targetHeight = h.toString();
    }
    this.targetWidth = value;
  }

  private onHeightChange(value: string) {
    const h = parseInt(value);
    if (!isNaN(h) && h > 0 && this.isRatioLocked) {
      // 等比例锁定：根据高度计算宽度
      const w = Math.round(h * (this.originalWidth / this.originalHeight));
      this.targetWidth = w.toString();
    }
    this.targetHeight = value;
  }

  // 切换锁状态时，确保宽高匹配
  private onLockToggle(isOn: boolean) {
    this.isRatioLocked = isOn;
    if (isOn) {
      // 开启锁：根据当前宽度重新计算高度
      const w = parseInt(this.targetWidth);
      if (!isNaN(w) && w > 0) {
        const h = Math.round(w * (this.originalHeight / this.originalWidth));
        this.targetHeight = h.toString();
      } else {
        // 若宽度无效，重置为原图尺寸
        this.targetWidth = this.originalWidth.toString();
        this.targetHeight = this.originalHeight.toString();
      }
    }
  }

  // ---------- FFmpeg 缩放 ----------
  private buildResizeCommand(inputPath: string, outputPath: string): string[] {
    const w = parseInt(this.targetWidth) || this.originalWidth;
    const h = parseInt(this.targetHeight) || this.originalHeight;
    let filter = '';
    if (this.isRatioLocked) {
      // 等比例缩放：保持比例，短边填满（不裁剪）
      filter = `scale=${w}:${h}:force_original_aspect_ratio=decrease`;
    } else {
      // 自由拉伸：强制改变宽高
      filter = `scale=${w}:${h}`;
    }
    return ['-i', inputPath, '-vf', filter, '-y', outputPath];
  }

  // ---------- 导出流程 ----------
  private cancelProcess(): void {
    if (this.currentSessionId > 0) {
      stopCommand({ sessionId: this.currentSessionId });
    }
    this.cancelFlag = true;
  }

  private startExport() {
    if (this.isExporting) return;
    const w = parseInt(this.targetWidth);
    const h = parseInt(this.targetHeight);
    if (!w || !h || w <= 0 || h <= 0) {
      promptAction.showToast({ message: '请输入有效的宽度和高度' });
      return;
    }

    this.cancelFlag = false;
    this.isExporting = true;

    this.progressDialogController = new CustomDialogController({
      builder: ProcessingDialog({
        processingText: '缩放图片中...',
        secondaryText: '缩放图片可能需要一些时间。',
        onCancel: () => this.cancelProcess()
      }),
      autoCancel: false,
      customStyle: true,
      cancel: () => this.cancelProcess()
    });
    this.progressDialogController.open();

    const cacheDir = this.context.cacheDir + '/tools/stretch/';
    const inputPath = cacheDir + 'source.png';
    const outputPath = cacheDir + 'stretched.png';
    try { fileIo.unlinkSync(outputPath); } catch {}

    const args = this.buildResizeCommand(inputPath, outputPath);
    console.info('FFmpeg 缩放参数:', args.join(' '));

    executeCommand({
      cmd: args.join(' '),
      start: (result: FfmpegResult) => {
        this.currentSessionId = result.sessionId ?? -1;
      },
      success: (result: FfmpegResult) => {
        if (!this.cancelFlag && this.isPageAlive) {
          this.saveToGallery(outputPath);
        } else {
          try { fileIo.unlinkSync(outputPath); } catch {}
        }
        this.closeProgressDialog();
        this.isExporting = false;
      },
      fail: (error: FfmpegError) => {
        console.error('缩放任务失败:', error);
        if (this.isPageAlive && !this.cancelFlag) {
          promptAction.showToast({ message: `缩放失败: ${error.message || '未知错误'}` });
        }
        try { fileIo.unlinkSync(outputPath); } catch {}
        this.closeProgressDialog();
        this.isExporting = false;
      },
      cancel: (result: FfmpegResult) => {
        try { fileIo.unlinkSync(outputPath); } catch {}
        if (this.isPageAlive) {
          promptAction.showToast({ message: '已取消缩放' });
        }
        this.closeProgressDialog();
        this.isExporting = false;
      },
      complete: (result: FfmpegResult) => {
        this.currentSessionId = -1;
      }
    });
  }

  private closeProgressDialog() {
    if (this.progressDialogController) {
      try { this.progressDialogController.close(); } catch {}
      this.progressDialogController = null;
    }
  }

  private async saveToGallery(filePath: string): Promise<void> {
    try {
      const phHelper = photoAccessHelper.getPhotoAccessHelper(this.context);
      const configs: photoAccessHelper.PhotoCreationConfig[] = [
        {
          title: `缩放_${Date.now()}`,
          fileNameExtension: 'png',
          photoType: photoAccessHelper.PhotoType.IMAGE,
          subtype: photoAccessHelper.PhotoSubtype.DEFAULT,
        }
      ];
      const destUris = await phHelper.showAssetsCreationDialog([filePath], configs);
      if (!destUris || destUris.length === 0) throw new Error('用户取消保存');
      const srcFile = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
      const destFile = fileIo.openSync(destUris[0], fileIo.OpenMode.WRITE_ONLY);
      fileIo.copyFileSync(srcFile.fd, destFile.fd);
      fileIo.closeSync(srcFile);
      fileIo.closeSync(destFile);
      if (this.isPageAlive) {
        promptAction.showToast({ message: '缩放图片已保存到相册' });
        router.back();
      }
    } catch (err) {
      console.error('保存到图库失败:', err);
      if (this.isPageAlive) {
        promptAction.showToast({ message: `保存失败: ${(err as Error).message || '未知错误'}` });
      }
    } finally {
      try { fileIo.unlinkSync(filePath); } catch {}
    }
  }

  // ---------- UI 组件 ----------
  @Builder
  buildTopBar() {
    Row() {
      Button() {
        SymbolGlyph($r('sys.symbol.arrow_left'))
          .fontSize(24).width(24).height(24)
          .fontColor([$r('sys.color.font_primary')])
      }
      .onClick(() => {
        if (this.isExporting) {
          promptAction.showToast({ message: '正在处理，请使用"取消"按钮停止' });
        } else {
          router.back();
        }
      })
      .height(40).width(40).buttonStyle(ButtonStyleMode.TEXTUAL)

      Text('图片缩放')
        .layoutWeight(1)
        .fontSize(18)
        .fontColor($r('sys.color.font_primary'))
        .fontWeight(FontWeight.Medium)
        .textAlign(TextAlign.Start)
    }
    .width('100%').height(56)
    .padding({ left: 16, right: 16 })
    .backgroundColor($r('sys.color.background_primary'))
    .shadow({ radius: 2, color: '#1A000000', offsetY: 1 })
  }

  // buildPreview 修改：固定 contain，无叠加层
  @Builder
  buildPreview() {
    Stack() {
      Image(`file://${this.previewPath}`)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Contain) // 始终 contain
        .backgroundColor(Color.Black)
    }
    .width('100%')
    .layoutWeight(1)
    .clip(true)
  }

  @Builder
  buildControlPanel() {
    Column({ space: 10 }) {
      Row({space:16}) {
        Column({space:4}) {
          Text('原图宽度')
            .fontSize(16)
            .fontColor($r('sys.color.font_primary'))
          TextInput({ text: this.originalWidth.toString(), placeholder: '宽' })
            .width('100%')
            .height(40)
            .type(InputType.Number)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .enabled(false)
        }
        .layoutWeight(1)

        Column({space:4}) {
          Text('原图高度')
            .fontSize(16)
            .fontColor($r('sys.color.font_primary'))
          TextInput({ text: this.originalHeight.toString(), placeholder: '高' })
            .width('100%')
            .height(40)
            .type(InputType.Number)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .enabled(false)
        }
        .layoutWeight(1)
      }
      .width('100%')

      Row() {
        Toggle({ type: ToggleType.Switch, isOn: this.isRatioLocked })
          .selectedColor($r('app.color.brand'))
          .onChange((isOn: boolean) => {
            this.onLockToggle(isOn);
          })
          .height(32)
          .width(60)
        Text('等比例缩放')
          .fontSize(16)
          .fontColor($r('sys.color.font_primary'))
          .margin({ left: 8 })
          .layoutWeight(1)
      }
      .width('100%')

      Row({space:16}) {
        Column({space:4}) {
          Text('宽度')
            .fontSize(16)
            .fontColor($r('sys.color.font_primary'))
          TextInput({ text: this.targetWidth, placeholder: '宽' })
            .width('100%')
            .height(40)
            .type(InputType.Number)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .onChange((value: string) => {
              this.onWidthChange(value);
            })
            .onFocus(() => {
              this.targetWidth = '';
            })
        }
        .layoutWeight(1)

        Column({space:4}) {
          Text('高度')
            .fontSize(16)
            .fontColor($r('sys.color.font_primary'))
          TextInput({ text: this.targetHeight, placeholder: '高' })
            .width('100%')
            .height(40)
            .type(InputType.Number)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .onChange((value: string) => {
              this.onHeightChange(value);
            })
            .onFocus(()=>{
              this.targetHeight = '';
            })
        }
        .layoutWeight(1)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ top: 12, bottom: 16, left:16,right:16 })
  }

  build() {
    Column() {
      this.buildTopBar();

      if (this.isLoading) {
        Column() {
          LoadingProgress().width(48).height(48)
          Text('加载图片中...').fontSize(16).fontColor($r('sys.color.font_secondary')).margin({ top: 12 })
        }
        .layoutWeight(1).justifyContent(FlexAlign.Center).width('100%')
      } else {
        this.buildPreview()

        Column() {
          this.buildControlPanel()

          Button('缩放并导出')
            .height(48)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .backgroundColor($r('app.color.brand'))
            .fontColor(Color.White)
            .borderRadius(24)
            .onClick(() => this.startExport())
            .enabled(!this.isExporting && parseInt(this.targetWidth) > 0 && parseInt(this.targetHeight) > 0)
            .width('90%')
        }
        .width('100%')
        .backgroundColor($r('sys.color.background_tertiary'))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_tertiary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}