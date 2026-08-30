import { showAbout } from '../common/ShowAbout';
import { getVideoInfo, VideoToGIF } from '../common/VideoUtils';
import { BusinessError } from '@kit.BasicServicesKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { common } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
import taskpool from '@ohos.taskpool';
import { fileIo as fs } from '@kit.CoreFileKit';

// ---------- 用于 TaskPool 的并发函数 ----------
@Concurrent
async function convertVideoTask(
  videoUri: string,
  context: common.UIAbilityContext,
  fps: number,
  width: number,
  maxLength: number,
  twoSteps: boolean
): Promise<string | null> {
  return await VideoToGIF(videoUri, context, fps, width, maxLength, twoSteps);
}

// ---------- 参数设置弹窗 ----------
@CustomDialog
struct GifSettingsDialog {
  controller: CustomDialogController;
  videoUri: string = '';
  context: common.UIAbilityContext = {} as common.UIAbilityContext;

  @State fps: number = 12;
  @State targetWidth: number = 480;
  @State maxLength: number = 5;
  @State useTwoSteps: boolean = true;

  private fpsOptions: SelectOption[] = [
    { value: '10' },
    { value: '12' },
    { value: '15' }
  ];
  private widthOptions: SelectOption[] = [
    { value: '360' },
    { value: '480' },
    { value: '640' },
    { value: '720' }
  ];

  private progressDialogController: CustomDialogController | null = null;
  private isCancelled: boolean = false;

  build() {
    Column({ space: 12 }) {
      Text('视频转GIF')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)

      Row() {
        Text('帧率')
          .width(80)
        Select(this.fpsOptions)
          .value(this.fpsOptions[1].value)
          .selected(1)
          .onSelect((index: number) => {
            this.fps = parseInt(this.fpsOptions[index].value as string, 10);
          })
          .layoutWeight(1)
      }

      Row() {
        Text('宽度')
          .width(80)
        Select(this.widthOptions)
          .value(this.widthOptions[1].value)
          .selected(1)
          .onSelect((index: number) => {
            this.targetWidth = parseInt(this.widthOptions[index].value as string, 10);
          })
          .layoutWeight(1)
      }

      Row() {
        Text('最高时长')
          .width(80)
        Slider({
          min: 1,
          max: 10,
          step: 0.5,
          value: this.maxLength
        })
          .onChange((value: number) => { this.maxLength = value; })
          .layoutWeight(1)
        Text(`${this.maxLength.toFixed(1)}秒`)
          .width(60)
          .textAlign(TextAlign.End)
      }

      Row() {
        Text('两步法调色盘')
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.useTwoSteps })
          .onChange((isOn: boolean) => { this.useTwoSteps = isOn; })
      }

      Row({ space: 20 }) {
        Button('取消')
          .onClick(() => this.controller.close())
          .buttonStyle(ButtonStyleMode.NORMAL)
          .layoutWeight(1)

        Button('转换')
          .onClick(() => {
            this.controller.close();
            this.startConversion();
          })
          .layoutWeight(1)
      }
      .width('100%')
    }
    .padding(20)
    .borderRadius(12)
  }

  private startConversion() {
    this.progressDialogController = new CustomDialogController({
      builder: GifProgressDialog({
        cancelCallback: () => {
          this.isCancelled = true;
        }
      })
    });
    this.progressDialogController.open();

    taskpool.execute(
      convertVideoTask,
      this.videoUri,
      this.context,
      this.fps,
      this.targetWidth,
      this.maxLength,
      this.useTwoSteps
    ).then((value: Object) => {
      const resultPath = value as string | null;
      this.progressDialogController?.close();
      if (this.isCancelled) {
        if (resultPath) {
          try { fs.unlinkSync(resultPath); } catch {}
        }
        promptAction.showToast({ message: '已取消转换' });
        return;
      }
      if (resultPath) {
        this.saveToGallery(resultPath);
      } else {
        promptAction.showToast({ message: '转换失败' });
      }
    }).catch((err: Error) => {
      this.progressDialogController?.close();
      promptAction.showToast({ message: '转换异常: ' + err.message });
    });
  }

  private async saveToGallery(filePath: string) {
    try {
      const phHelper = photoAccessHelper.getPhotoAccessHelper(this.context);
      const timestamp = Date.now();
      const configs: photoAccessHelper.PhotoCreationConfig[] = [
        {
          title: `GIF_${timestamp}`,
          fileNameExtension: 'gif',
          photoType: photoAccessHelper.PhotoType.IMAGE,
          subtype: photoAccessHelper.PhotoSubtype.DEFAULT,
        }
      ];
      const destUris: string[] = await phHelper.showAssetsCreationDialog([filePath], configs);
      if (!destUris || destUris.length === 0) {
        throw new Error('用户取消保存');
      }
      const destUri = destUris[0];
      const srcFile = fs.openSync(filePath, fs.OpenMode.READ_ONLY);
      const destFile = fs.openSync(destUri, fs.OpenMode.WRITE_ONLY);
      fs.copyFileSync(srcFile.fd, destFile.fd);
      fs.closeSync(srcFile);
      fs.closeSync(destFile);
      promptAction.showToast({ message: 'GIF已保存到相册' });
    } catch (err) {
      console.error('保存到图库失败:', err);
      promptAction.showToast({ message: '保存失败: ' + (err.message || '未知错误') });
    } finally {
      try { fs.unlinkSync(filePath); } catch {}
    }
  }
}

// ---------- 转换进度弹窗 ----------
@CustomDialog
struct GifProgressDialog {
  controller: CustomDialogController;
  cancelCallback: () => void = () => {};

  build() {
    Column({ space: 16 }) {
      LoadingProgress()
        .width(48)
        .height(48)
      Text('转换中...')
        .fontSize(18)
        .fontColor($r('sys.color.font_primary'))
      Text('转换为GIF可能需要一段时间。')
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
      Button('取消')
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .onClick(() => {
          this.cancelCallback();
          this.controller.close();
        })
        .width('100%')
    }
    .padding(24)
    .borderRadius(12)
  }
}

// ---------- 主组件 ----------
@Component
export struct ToolsContent {
  private settingsDialogController: CustomDialogController | null = null;
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;

  // ====== 清理缓存工具 ======
  private async cleanToolsCache(): Promise<void> {
    try {
      const cacheDir = this.context.cacheDir;
      if (!cacheDir) return;
      const toolsDir = cacheDir + '/tools/';
      // 尝试删除整个 tools 目录
      try {
        if (fs.accessSync(toolsDir)) {
          this.deleteDirectoryRecursive(toolsDir);
          console.info('已清理 cache/tools/');
        }
      } catch (e) {
        // 目录不存在，忽略
      }
    } catch (e) {
      console.warn('清理 tools 缓存失败:', e);
    }
  }

  private deleteDirectoryRecursive(path: string): void {
    try {
      const files = fs.listFileSync(path);
      for (const file of files) {
        const fullPath = `${path}/${file}`;
        const stat = fs.statSync(fullPath);
        if (stat.isDirectory()) {
          this.deleteDirectoryRecursive(fullPath);
        } else {
          fs.unlinkSync(fullPath);
        }
      }
      fs.rmdirSync(path);
    } catch (e) {
      console.warn('删除目录失败:', path, e);
    }
  }

  private async pickVideo(): Promise<string | null> {
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.VIDEO_TYPE;
      options.maxSelectNumber = 1;
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const result = await photoPicker.select(options);
      if (result.photoUris.length === 0) {
        promptAction.showToast({ message: '未选择视频' });
        return null;
      }
      return result.photoUris[0];
    } catch (err) {
      console.error('选择视频失败:', err);
      promptAction.showToast({ message: '选择视频失败' });
      return null;
    }
  }

  private async doGetVideoInfo() {
    await this.cleanToolsCache();
    const uri = await this.pickVideo();
    if (!uri) return;
    const videoInfo = await getVideoInfo(uri, this.context);
    if (videoInfo) {
      router.pushUrl({
        url: 'pages/VideoInfoPage',
        params: { videoInfo: JSON.stringify(videoInfo) }
      });
    } else {
      promptAction.showToast({ message: "获取视频信息失败" });
    }
  }

  // ====== 视频转GIF ======
  private async pickVideoAndShowSettings() {
  await this.cleanToolsCache();
  const uri = await this.pickVideo();
  if (!uri) return;
  this.settingsDialogController = new CustomDialogController({
    builder: GifSettingsDialog({
      videoUri: uri,
      context: this.context
    })
  });
  this.settingsDialogController.open();
}

  // ====== 视频帧截取 ======
  private async pickVideoForCapture() {
  await this.cleanToolsCache();
  const uri = await this.pickVideo();
  if (!uri) return;
  router.pushUrl({
    url: 'pages/FrameCapturePage',
    params: { videoUri: uri }
  });
}

  // ====== 视频画面裁剪 ======
  private async pickVideoForCrop() {
    await this.cleanToolsCache();
    const uri = await this.pickVideo();
    if (!uri) return;
    router.pushUrl({
      url: 'pages/VideoCropPage',
      params: { videoUri: uri }
    });
  }

  // 在 pickVideoForRotate 方法中，改为跳转页面
  private async pickVideoForRotate() {
  await this.cleanToolsCache();
  const uri = await this.pickVideo();
  if (!uri) return;
  router.pushUrl({
    url: 'pages/VideoRotatePage',
    params: { videoUri: uri }
  });
}

  private async pickVideoForWatermark() {
    await this.cleanToolsCache();
    const uri = await this.pickVideo();
    if (!uri) return;
    router.pushUrl({
      url: 'pages/AddWatermarkPage',
      params: { videoUri: uri }
    });
  }

  private async pickVideoForImageWatermark() {
    try {
      await this.cleanToolsCache();

      // 1. 选择视频
      const videoUri = await this.pickVideo();
      if (!videoUri) return;

      // 2. 选择图片
      const imageOptions = new photoAccessHelper.PhotoSelectOptions();
      imageOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      imageOptions.maxSelectNumber = 1;
      const imagePicker = new photoAccessHelper.PhotoViewPicker();
      const imageResult = await imagePicker.select(imageOptions);
      if (!imageResult || imageResult.photoUris.length === 0) {
        promptAction.showToast({ message: '未选择图片' });
        return;
      }
      const imageUri = imageResult.photoUris[0];

      // 3. 跳转到图片水印页面，同时传递视频和图片URI
      router.pushUrl({
        url: 'pages/AddImageWatermarkPage',
        params: {
          videoUri: videoUri,
          imageUri: imageUri
        }
      });
    } catch (err) {
      console.error('选择视频或图片失败:', err);
      promptAction.showToast({ message: '选择失败' });
    }
  }

  // ====== UI 工具 ======
  @Builder
  buildTool(toolIcon: Resource, toolName: string, toolAction: () => void) {
    Row() {
      SymbolGlyph(toolIcon)
        .width(28)
        .height(28)
        .fontSize(28)
        .fontColor([$r('sys.color.font_primary')])
        .margin({ right: 16 })
      Text(toolName)
        .fontSize(16)
        .fontColor($r('sys.color.font_primary'))
        .textAlign(TextAlign.Start)
      Blank()
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .width(32)
        .height(32)
        .fontSize(32)
        .fontColor([$r('sys.color.font_tertiary')])
    }
    .width('100%')
    .height(56)
    .borderRadius(16)
    .onClick(toolAction)
    .padding({ left: 16, right: 4 })
    .stateStyles({
      pressed: { .backgroundColor($r('app.color.listitem_pressed')) },
      normal: { .backgroundColor($r('app.color.listitem')) }
    })
  }

  @Builder
  buildDivider() {
    Divider().padding({ left: 8, right: 8 }).strokeWidth(0.8)
  }

  build() {
    Stack() {
      List({ space: 12 }) {
        ListItem() {
          Column() {
            this.buildTool($r('sys.symbol.list_bullet'), "获取视频属性", () => {
              this.doGetVideoInfo();
            });
            this.buildDivider();
            this.buildTool($r('sys.symbol.gif_video'), "视频转GIF", () => {
              this.pickVideoAndShowSettings();
            });
            this.buildDivider();
            this.buildTool($r('sys.symbol.screenshot'), "视频单帧提取", () => {
              this.pickVideoForCapture();
            });
            this.buildDivider();
            this.buildTool($r('sys.symbol.crop'), "视频画面裁剪", () => {
              this.pickVideoForCrop();
            });
            this.buildDivider();
            this.buildTool($r('sys.symbol.rotate_left'), "视频旋转", () => {
              this.pickVideoForRotate();
            });
            this.buildDivider();
            this.buildTool($r('sys.symbol.watermark_font'), "添加文字水印", () => {
              this.pickVideoForWatermark();
            });
            this.buildDivider();
            this.buildTool($r('sys.symbol.star_square_on_square'),"添加图片水印",()=>{
              this.pickVideoForImageWatermark();
            });
          }
          .backgroundColor($r('app.color.listitem'))
          .borderRadius(16)
          .padding(4)
        }
        .padding({ left: 12, right: 12 })

        ListItem() {
          Column() {
            this.buildTool($r('sys.symbol.info_circle'), "关于", () => showAbout());
          }
          .backgroundColor($r('app.color.listitem'))
          .borderRadius(16)
          .padding(4)
        }
        .padding({ left: 12, right: 12 })
      }
      .width('100%')
      .align(Alignment.Top)
      .alignListItem(ListItemAlign.Center)
      .contentStartOffset(56)
      .contentEndOffset(80)

      Row() {
        Text($r('app.string.video_tools'))
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .position({ x: 0, y: 0 })
      .zIndex(1)
      .backgroundColor('#00000000')
      .linearGradient({
        angle: 0,
        colors: [
          [$r('app.color.titlebar_gradient_end'), 0.0],
          [$r('sys.color.background_secondary'), 1.0]
        ]
      })
    }
    .alignContent(Alignment.TopStart)
    .width('100%')
    .height('100%')
  }
}