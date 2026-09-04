import { FrameData } from '../model/FrameData';
import { ItemState, ToolBar, ToolBarOption, ToolBarOptions } from '@kit.ArkUI';

@Component
export struct FrameList {
  @Prop frames: FrameData[] = [];
  @Prop currentIndex: number = -1;
  onSelect: (idx: number) => void = () => {};
  onMove: (from: number, to: number) => void = () => {};
  onDelete: (idx: number) => void = () => {};
  onAdd: () => void = () => {};
  @Prop isWideScreen: boolean = false;

  @State FrameTools: ToolBarOptions = [
    {
      content:'删除帧',
      icon:$r('sys.symbol.trash'),
      state:(this.currentIndex == -1) ? ItemState.DISABLE : ItemState.ENABLE,
      action:()=>{
        if(this.currentIndex != -1) this.onDelete(this.currentIndex);
      }
    },
    {
      content:'添加帧',
      icon:$r('sys.symbol.plus'),
      action:()=>this.onAdd()
    }
  ]

  @Builder
  buildFrameList(){
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
          .width(48)
          .height(48)
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .bindMenu([
            {
              value: '上移', action: () => {
              if (index > 0) this.onMove(index, index - 1);
            }
            },
            {
              value: '下移', action: () => {
              if (index < this.frames.length - 1) this.onMove(index, index + 1);
            }
            },
            {
              value: '移最上面', action: () => {
              if (index > 0) this.onMove(index, 0);
            }
            },
            {
              value: '移最下面', action: () => {
              if (index < this.frames.length - 1) this.onMove(index, this.frames.length - 1);
            }
            },
            { value: '删除', action: () => this.onDelete(index) }
          ])
        }
        .width('100%')
        .height(72)
        .padding({ left: 8, right: 8 })
        .backgroundColor(
          index === this.currentIndex ? $r('app.color.selected_frame') : $r('sys.color.background_tertiary'))
        .borderRadius(4)
        .onClick(() => this.onSelect(index))
      }
    }, (frame: FrameData) => frame.id)
  }

  @Builder
  buildVerticalToolBar(){
    Column({space:12}){
      ForEach(this.FrameTools,(item: ToolBarOption,index: number)=>{
        Button(){
          Column(){
            SymbolGlyph(item.icon)
              .fontColor([$r('sys.color.font_primary')])
              .fontSize(32)
              .width(32)
              .height(32)
            Text(item.content)
              .fontColor($r('sys.color.font_primary'))
              .textAlign(TextAlign.Center)
          }
        }
        .padding({left:8,right:8})
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .layoutWeight(1)
        .onClick(()=>{
          item.action?.()
        })
      })
    }
  }

  build() {
    if(this.isWideScreen) {
      Column() {
        List({ space: 2 }) {
          this.buildFrameList();
        }
        .width('100%')
        .layoutWeight(1)

        ToolBar({
          toolBarList: this.FrameTools
        })
          .width('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('sys.color.background_tertiary'))
    }else{
      Row(){
        List({ space: 2 }) {
          this.buildFrameList();
        }
        .width('100%')
        .layoutWeight(1)

        Divider()
          .vertical(true)

        this.buildVerticalToolBar();
      }
    }
  }
}