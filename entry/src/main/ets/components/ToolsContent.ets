import { showAbout } from '../common/ShowAbout'

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
              // TODO: 完成查看视频属性
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
              Text('另一个按钮')
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
              // TODO: 视频加水印
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