import { FrameData } from '../model/FrameData';

@Component
export struct FrameList {
  @Prop frames: FrameData[] = [];
  @Prop currentIndex: number = -1;
  onSelect: (idx: number) => void = () => {};
  onMove: (from: number, to: number) => void = () => {};
  onDelete: (idx: number) => void = () => {};
  onAdd: () => void = () => {};

  build() {
    Column() {
      List({ space: 2 }) {
        ForEach(this.frames, (frame: FrameData, index: number) => {
          ListItem() {
            Row() {
              Text(`${index + 1}`)
                .width(30)
                .fontSize(16)
                .fontColor($r('sys.color.font_primary'))
                .textAlign(TextAlign.Center)

              if (frame.uri) {
                Image(frame.uri)
                  .width(80)
                  .height(60)
                  .objectFit(ImageFit.Cover)
                  .borderRadius(4)
                  .margin({ left: 4, right: 8 })
              } else {
                Image($r('app.media.placeholder'))
                  .width(80)
                  .height(60)
                  .borderRadius(4)
                  .margin({ left: 4, right: 8 })
              }

              Button() {
                SymbolGlyph($r('sys.symbol.dot_grid_1x2'))
                  .fontSize(28)
                  .width(28)
                  .height(28)
                  .fontColor([$r('sys.color.font_primary')])
              }
              .width(32)
              .height(32)
              .buttonStyle(ButtonStyleMode.TEXTUAL)
              .bindMenu([
                { value: '上移', action: () => { if (index > 0) this.onMove(index, index - 1); } },
                { value: '下移', action: () => { if (index < this.frames.length - 1) this.onMove(index, index + 1); } },
                { value: '删除', action: () => this.onDelete(index) }
              ])
            }
            .width('100%')
            .height(72)
            .padding({ left: 8, right: 8 })
            .backgroundColor(index === this.currentIndex ? $r('app.color.selected_frame') : $r('sys.color.background_tertiary'))
            .borderRadius(4)
            .onClick(() => this.onSelect(index))
          }
        }, (frame: FrameData) => frame.id)  // ★ 关键：使用唯一 id 作为 key
      }
      .width('100%')
      .layoutWeight(1)

      Button('添加帧')
        .width('100%')
        .height(48)
        .backgroundColor($r('sys.color.brand'))
        .fontColor(Color.White)
        .onClick(() => this.onAdd())
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_tertiary'))
  }
}