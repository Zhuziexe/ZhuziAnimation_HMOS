import { showAbout } from '../common/ShowAbout'
import { getVideoInfo } from '../common/VideoUtils'
import { BusinessError } from '@kit.BasicServicesKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';

async function doGetVideoInfo(ctx: common.UIAbilityContext) {
  try {
    let PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
    PhotoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.VIDEO_TYPE;
    PhotoSelectOptions.maxSelectNumber = 1;

    let photoPicker = new photoAccessHelper.PhotoViewPicker();
    const PhotoSelectResult = await photoPicker.select(PhotoSelectOptions);
    if (PhotoSelectResult.photoUris.length === 1) {
      const uri = PhotoSelectResult.photoUris[0];
      console.info('选中视频 URI: ' + uri);

      // 获取视频信息
      const videoInfo = await getVideoInfo(uri, ctx);

      console.info(JSON.stringify(videoInfo));

      if (videoInfo) {
        // 跳转到 VideoInfoPage，通过 params 传递数据（转成 JSON 字符串）
        router.pushUrl({
          url: 'pages/VideoInfoPage', // 根据实际路径修改
          params: { videoInfo: JSON.stringify(videoInfo) }
        });
      } else {
        // 提示获取失败
        console.warn('获取视频信息失败');
      }
    }
  } catch (error) {
    let err: BusinessError = error as BusinessError;
    console.error(`选择或获取视频失败: ${err.code}, ${err.message}`);
  }
}

@Component
export struct ToolsContent{
  build(){
    Stack() {
      List({space:12}) {
        ListItem() {
          Column(){
            Row() {
              SymbolGlyph($r('sys.symbol.list_square_bill'))
                .width(28)
                .height(28)
                .fontSize(28)
                .fontColor([$r('sys.color.font_primary')])
                .margin({ right: 16 })

              Text('获取视频属性')
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
            .onClick(() => {
              doGetVideoInfo(this.getUIContext().getHostContext() as common.UIAbilityContext);
            })
            .padding({left:16,right:4})
            .stateStyles({
              pressed: {
                .backgroundColor($r('app.color.listitem_pressed'))
              },
              normal:{
                .backgroundColor($r('app.color.listitem'))
              }
            })
            Divider()
              .padding({left:8,right:8})
            Row() {
              SymbolGlyph($r('sys.symbol.watermark_font'))
                .width(28)
                .height(28)
                .fontSize(28)
                .fontColor([$r('sys.color.font_primary')])
                .margin({ right: 16 })
              Text('敬请期待')
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
            .onClick(() => {
              // TODO: 敬请期待
            })
            .padding({left:16,right:4})
            .stateStyles({
              pressed: {
                .backgroundColor($r('app.color.listitem_pressed'))
              },
              normal:{
                .backgroundColor($r('app.color.listitem'))
              }
            })
          }
          .backgroundColor($r('app.color.listitem'))
          .borderRadius(16)
          .padding(4)
        }
        .padding({left:12,right:12})
        ListItem() {
          Column(){
            Row() {
              SymbolGlyph($r('sys.symbol.info_circle'))
                .width(28)
                .height(28)
                .fontSize(28)
                .fontColor([$r('sys.color.font_primary')])
                .margin({ right: 16 })

              Text('关于')
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
            .onClick(() => {
              showAbout()
            })
            .padding({left:16,right:4})
            .stateStyles({
              pressed: {
                .backgroundColor($r('app.color.listitem_pressed'))
              },
              normal:{
                .backgroundColor($r('app.color.listitem'))
              }
            })
          }
          .backgroundColor($r('app.color.listitem'))
          .borderRadius(16)
          .padding(4)
        }
        .padding({left:12,right:12})
      }
      .width('100%')
      .align(Alignment.Top)
      .alignListItem(ListItemAlign.Center)
      .contentStartOffset(56)
      .contentEndOffset(80)

      Row() {
        Text('小工具')
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