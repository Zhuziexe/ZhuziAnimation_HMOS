import { showAbout } from '../common/ShowAbout';
import { VideoToGIF, getVideoInfo } from '../common/VideoUtils';
import { BusinessError } from '@kit.BasicServicesKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { common } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
import taskpool from '@ohos.taskpool';
import { fileIo as fs } from '@kit.CoreFileKit';
import { ExtractAudioDialog } from '../components/ExtractAudioDialog';
import { VideoMuteDialog } from '../components/VideoMuteDialog';
import { GifSettingsDialog, GifProgressDialog } from '../components/VideoToGifDialog';

@Component
export struct ToolsContent {
  private settingsDialogController: CustomDialogController | null = null;
  private extractAudioDialogController: CustomDialogController | null = null;
  private videoMuteDialogController: CustomDialogController | null = null;
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;

  private async cleanToolsCache(): Promise<void> {
    try {
      const cacheDir = this.context.cacheDir;
      if (!cacheDir) return;
      const toolsDir = cacheDir + '/tools/';
      try {
        if (fs.accessSync(toolsDir)) {
          this.deleteDirectoryRecursive(toolsDir);
          console.info('已清理 cache/tools/');
        }
      } catch (e) {
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

  private async pickVideoForInfo() {
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

  private async pickVideoForGif() {
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

  private async pickVideoForPage(pageUrl: string) {
    await this.cleanToolsCache();
    const uri = await this.pickVideo();
    if(!uri) return;
    router.pushUrl({
      url: pageUrl,
      params:{videoUri:uri}
    });
  }

  private async pickVideoForOverlay() {
    try {
      await this.cleanToolsCache();
      const videoUri = await this.pickVideo();
      if (!videoUri) return;

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

      router.pushUrl({
        url: 'pages/AddImageOverlayPage',
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

  private async pickVideoForExtractAudio() {
    await this.cleanToolsCache();
    const videoUri = await this.pickVideo();
    if (!videoUri) return;

    if (this.extractAudioDialogController) {
      this.extractAudioDialogController.close();
      this.extractAudioDialogController = null;
    }
    this.extractAudioDialogController = new CustomDialogController({
      builder: ExtractAudioDialog({
        videoUri: videoUri
      }),
      alignment: DialogAlignment.Center,
      autoCancel: false,
    });
    this.extractAudioDialogController.open();
  }

  private async pickVideoForMute() {
    const videoUri = await this.pickVideo();
    if (!videoUri) return;

    if (this.videoMuteDialogController) {
      this.videoMuteDialogController.close();
      this.videoMuteDialogController = null;
    }
    this.videoMuteDialogController = new CustomDialogController({
      builder: VideoMuteDialog({
        videoUri: videoUri
      }),
      alignment: DialogAlignment.Center,
      autoCancel: false,
    });
    this.videoMuteDialogController.open();
  }

  private async pickImageForBlur() {
    try {
      await this.cleanToolsCache();
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const result = await photoPicker.select(options);
      if (result.photoUris.length === 0) {
        promptAction.showToast({ message: '未选择图片' });
        return;
      }
      const uri = result.photoUris[0];
      router.pushUrl({
        url: 'pages/ImageBlurPage',
        params: { imageUri: uri }
      });
    } catch (err) {
      console.error('选择图片失败:', err);
      promptAction.showToast({ message: '选择图片失败' });
    }
  }

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
              this.pickVideoForInfo();
            });
            this.buildDivider();
            this.buildTool($r('sys.symbol.gif_video'), "视频转GIF", () => {
              this.pickVideoForGif();
            });
            this.buildDivider();
            this.buildTool($r('sys.symbol.arrow_up_and_rectangle_on_rectangle'), "视频单帧提取", () => {
              this.pickVideoForPage('pages/FrameCapturePage');
            });
            this.buildDivider();
            this.buildTool($r('sys.symbol.crop'), "视频画面裁剪", () => {
              this.pickVideoForPage('pages/VideoCropPage');
            });
            this.buildDivider();
            this.buildTool($r('sys.symbol.rotate_left'), "视频旋转", () => {
              this.pickVideoForPage('pages/VideoRotatePage');
            });
            this.buildDivider();
            this.buildTool($r('sys.symbol.character_square'), "添加文字水印", () => {
              this.pickVideoForPage('pages/AddWatermarkPage');
            });
            this.buildDivider();
            this.buildTool($r('sys.symbol.star_square_on_square'),"叠加图片到视频",()=>{
              this.pickVideoForOverlay();
            });
            this.buildDivider();
            this.buildTool($r('sys.symbol.make_video'), "视频区域模糊", () => {
              this.pickVideoForPage('pages/VideoBlurPage');
            });
            this.buildDivider();
            this.buildTool($r('sys.symbol.square_split_2x1_dash'), "图片区域模糊", () => {
              this.pickImageForBlur();
            });
          }
          .backgroundColor($r('app.color.listitem'))
          .borderRadius(16)
          .padding(4)
        }
        .padding({ left: 12, right: 12 })

        ListItem() {
          Column() {
            this.buildTool($r('sys.symbol.music_slash_fill'),"去除视频音频",()=>{
              this.pickVideoForMute();
            });
            this.buildDivider();
            this.buildTool($r('sys.symbol.wave_video'), "提取视频音频", () => {
              this.pickVideoForExtractAudio();
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