import { getVideoInfo } from '../common/VideoUtils';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { common } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { ExtractAudioDialog } from '../components/ExtractAudioDialog';
import { VideoMuteDialog } from '../components/VideoMuteDialog';
import { GifSettingsDialog } from '../components/VideoToGifDialog';
import { SegmentButtonItemTuple, SegmentButton, SegmentButtonOptions } from '@kit.ArkUI';

@Component
export struct ToolsContent {
  private settingsDialogController: CustomDialogController | null = null;
  private extractAudioDialogController: CustomDialogController | null = null;
  private videoMuteDialogController: CustomDialogController | null = null;
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;

  @State tabOptions: SegmentButtonOptions = SegmentButtonOptions.capsule({
    buttons: [
      { text: '音视频' },
      { text: '图片' }
    ] as SegmentButtonItemTuple,
    selectedFontColor:$r('sys.color.font_primary'),
    backgroundColor: $r('app.color.unselected_tab_button'),
    selectedBackgroundColor:$r('app.color.selected_tab_button')
  });
  @StorageLink('toolIndex') selectedIndexes: number[] = [0];

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

  private async pickImage(): Promise<string | null> {
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const result = await photoPicker.select(options);
      if (result.photoUris.length === 0) {
        promptAction.showToast({ message: '未选择图片' });
        return null;
      }
      return result.photoUris[0];
    } catch (err) {
      console.error('选择图片失败:', err);
      promptAction.showToast({ message: '选择图片失败' });
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

      const imageUri = await this.pickImage();
      if (!imageUri) return;

      router.pushUrl({
        url: 'pages/VideoOverlayPage',
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

  private async pickImageForOverlay() {
    try {
      await this.cleanToolsCache();
      const baseUri = await this.pickImage();
      if (!baseUri) return;

      const overlayUri = await this.pickImage();
      if (!overlayUri) return;

      router.pushUrl({
        url: 'pages/ImageOverlayPage',
        params: {
          baseImageUri: baseUri,
          overlayImageUri: overlayUri
        }
      });
    } catch (err) {
      console.error('选择图片失败:', err);
      promptAction.showToast({ message: '选择图片失败' });
    }
  }

  private async pickImageForPage(pageUrl: string) {
    try {
      await this.cleanToolsCache();
      const uri = await this.pickImage();
      if (!uri) return;
      router.pushUrl({
        url: pageUrl,
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
        if(this.selectedIndexes[0] == 0) {
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
              this.buildTool($r('sys.symbol.character_square'), "视频文字水印", () => {
                this.pickVideoForPage('pages/VideoWatermarkPage');
              });
              this.buildDivider();
              this.buildTool($r('sys.symbol.star_square_on_square'), "叠加图片到视频", () => {
                this.pickVideoForOverlay();
              });
              this.buildDivider();
              this.buildTool($r('sys.symbol.make_video'), "视频区域模糊", () => {
                this.pickVideoForPage('pages/VideoBlurPage');
              });
              this.buildDivider();
              this.buildTool($r('sys.symbol.video_speed'), "视频变速", () => {
                this.pickVideoForPage('pages/VideoSpeedPage');
              });
              this.buildDivider();
              this.buildTool($r('sys.symbol.music_slash_fill'), "去除视频音频", () => {
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
        }

        if(this.selectedIndexes[0] == 1) {
          ListItem() {
            Column() {
              this.buildTool($r('sys.symbol.rotate_left'), "图片旋转", () => {
                this.pickImageForPage('pages/ImageRotatePage');
              });
              this.buildDivider();
              this.buildTool($r('sys.symbol.character_square'), "图片文字水印", () => {
                this.pickImageForPage('pages/ImageWatermarkPage');
              });
              this.buildDivider();
              this.buildTool($r('sys.symbol.star_square_on_square'), "图片叠加", () => {
                this.pickImageForOverlay();
              });
              this.buildDivider();
              this.buildTool($r('sys.symbol.square_split_2x1_dash'), "图片区域模糊", () => {
                this.pickImageForPage('pages/ImageBlurPage');
              });
              this.buildDivider();
              this.buildTool($r('sys.symbol.celiakeyboard_menu_icon_size'),"图片缩放",()=>{
                this.pickImageForPage('pages/ImageStretchPage');
              })
            }
            .backgroundColor($r('app.color.listitem'))
            .borderRadius(16)
            .padding(4)
          }
          .padding({ left: 12, right: 12 })
        }
      }
      .width('100%')
      .align(Alignment.Top)
      .alignListItem(ListItemAlign.Center)
      .contentStartOffset(110)
      .contentEndOffset(80)

      // 标题栏和分段按钮（保持不变）
      Column({space:4}) {
        Row() {
          Text($r('app.string.tools_page'))
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
        }
        .height(56)
        SegmentButton({
          options: this.tabOptions,
          selectedIndexes: this.selectedIndexes
        })
          .width('100%')
          .height(40)
          .padding(2)
      }
      .width('100%')
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