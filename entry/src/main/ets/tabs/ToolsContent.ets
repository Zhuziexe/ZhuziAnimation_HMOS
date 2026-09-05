import { getVideoInfo } from '../common/VideoUtils';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { ExtractAudioDialog } from '../components/ExtractAudioDialog';
import { VideoMuteDialog } from '../components/VideoMuteDialog';
import { GifSettingsDialog } from '../components/VideoToGifDialog';
import { SegmentButtonItemTuple, SegmentButton, SegmentButtonOptions } from '@kit.ArkUI';
import { VideoUriInterface, VideoInfoInterface, ImageUriInterface } from '../common/CommonInterfaces';
import { VideoOverlayParams } from '../pages/VideoOverlayPage';
import { ImageOverlayParams } from '../pages/ImageOverlayPage'

interface MiniTool {
  toolIcon: Resource;
  toolName: string;
  toolAction: () => void;
}

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
    selectedFontColor: $r('sys.color.font_primary'),
    backgroundColor: $r('app.color.unselected_tab_button'),
    selectedBackgroundColor: $r('app.color.selected_tab_button')
  });
  @StorageLink('toolIndex') selectedIndexes: number[] = [0];
  pathStack: NavPathStack = AppStorage.get('pathStack') as NavPathStack;

  private videoTools: MiniTool[] = [
    {
      toolIcon: $r('sys.symbol.list_bullet'),
      toolName: '获取视频属性',
      toolAction: () => { this.pickVideoForInfo(); }
    },
    {
      toolIcon: $r('sys.symbol.gif_video'),
      toolName: '视频转GIF',
      toolAction: () => { this.pickVideoForGif(); }
    },
    {
      toolIcon: $r('sys.symbol.arrow_up_and_rectangle_on_rectangle'),
      toolName: '视频单帧提取',
      toolAction: () => { this.pickVideoForPage('FrameCapturePage'); }
    },
    {
      toolIcon: $r('sys.symbol.crop'),
      toolName: '视频画面裁剪',
      toolAction: () => { this.pickVideoForPage('VideoCropPage'); }
    },
    {
      toolIcon: $r('sys.symbol.rotate_left'),
      toolName: '视频旋转',
      toolAction: () => { this.pickVideoForPage('VideoRotatePage'); }
    },
    {
      toolIcon: $r('sys.symbol.character_square'),
      toolName: '视频文字水印',
      toolAction: () => { this.pickVideoForPage('VideoWatermarkPage'); }
    },
    {
      toolIcon: $r('sys.symbol.star_square_on_square'),
      toolName: '叠加图片到视频',
      toolAction: () => { this.pickVideoForOverlay(); }
    },
    {
      toolIcon: $r('sys.symbol.make_video'),
      toolName: '视频区域模糊',
      toolAction: () => { this.pickVideoForPage('VideoBlurPage'); }
    },
    {
      toolIcon: $r('sys.symbol.video_speed'),
      toolName: '视频变速',
      toolAction: () => { this.pickVideoForPage('VideoSpeedPage'); }
    },
    {
      toolIcon: $r('sys.symbol.music_slash_fill'),
      toolName: '去除视频音频',
      toolAction: () => { this.pickVideoForMute(); }
    },
    {
      toolIcon: $r('sys.symbol.wave_video'),
      toolName: '提取视频音频',
      toolAction: () => { this.pickVideoForExtractAudio(); }
    }
  ];

  private imageTools: MiniTool[] = [
    {
      toolIcon: $r('sys.symbol.rotate_left'),
      toolName: '图片旋转',
      toolAction: () => { this.pickImageForPage('ImageRotatePage'); }
    },
    {
      toolIcon: $r('sys.symbol.character_square'),
      toolName: '图片文字水印',
      toolAction: () => { this.pickImageForPage('ImageWatermarkPage'); }
    },
    {
      toolIcon: $r('sys.symbol.star_square_on_square'),
      toolName: '图片叠加',
      toolAction: () => { this.pickImageForOverlay(); }
    },
    {
      toolIcon: $r('sys.symbol.square_split_2x1_dash'),
      toolName: '图片区域模糊',
      toolAction: () => { this.pickImageForPage('ImageBlurPage'); }
    },
    {
      toolIcon: $r('sys.symbol.celiakeyboard_menu_icon_size'),
      toolName: '图片缩放',
      toolAction: () => { this.pickImageForPage('ImageStretchPage'); }
    },
    {
      toolIcon: $r('sys.symbol.camera_filters'),
      toolName: '迷幻变色',
      toolAction: () => { this.pickImageForPage('ImageColorPage'); }
    },
    {
      toolIcon: $r('sys.symbol.eyedropper'),
      toolName: '图片取色器',
      toolAction: () => { this.pickImageForPage('ImageColorPickerPage'); }
    }
  ];

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
      this.pathStack.pushPath({
        name:'VideoInfoPage',
        param:{videoInfo:videoInfo} as VideoInfoInterface
      })
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
    if (!uri) return;
    this.pathStack?.pushPath({
      name:pageUrl,
      param:{ videoUri:uri } as VideoUriInterface
    })
  }

  private async pickVideoForOverlay() {
    try {
      await this.cleanToolsCache();
      const videoUri = await this.pickVideo();
      if (!videoUri) return;

      const imageUri = await this.pickImage();
      if (!imageUri) return;

      this.pathStack.pushPath({
        name:'VideoOverlayPage',
        param: {videoUri:videoUri,imageUri:imageUri} as VideoOverlayParams
      })
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

      this.pathStack.pushPath({
        name:'ImageOverlayPage',
        param:{baseImageUri:baseUri,overlayImageUri:overlayUri} as ImageOverlayParams
      })
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
      this.pathStack?.pushPath({
        name: pageUrl,
        param: { imageUri:uri } as ImageUriInterface
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
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .width(32)
        .height(32)
        .fontSize(32)
        .fontColor([$r('sys.color.font_tertiary')])
    }
    .hoverEffect(HoverEffect.Highlight)
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

  @Builder
  renderToolList(tools: MiniTool[]) {
    Column() {
      ForEach(tools,
        (item: MiniTool, index: number) => {
          if (index > 0) {
            this.buildDivider();
          }
          this.buildTool(item.toolIcon, item.toolName, item.toolAction);
        },
        (item: MiniTool) => item.toolName
      )
    }
    .backgroundColor($r('app.color.listitem'))
    .borderRadius(16)
    .padding(4)
  }

  build() {
    Stack() {
      List({ space: 12 }) {
        if (this.selectedIndexes[0] == 0) {
          ListItem() {
            this.renderToolList(this.videoTools)
          }
          .padding({ left: 12, right: 12 })
        }

        if (this.selectedIndexes[0] == 1) {
          ListItem() {
            this.renderToolList(this.imageTools)
          }
          .padding({ left: 12, right: 12 })
        }
      }
      .width('100%')
      .align(Alignment.Top)
      .alignListItem(ListItemAlign.Center)
      .contentStartOffset(110)
      .contentEndOffset(80)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      // 标题栏和分段按钮
      Column({ space: 4 }) {
        Row() {
          Text($r('app.string.tools_page'))
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
        }
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .height(56)
        SegmentButton({
          options: this.tabOptions,
          selectedIndexes: this.selectedIndexes
        })
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
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
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .alignContent(Alignment.TopStart)
    .width('100%')
    .height('100%')
  }
}