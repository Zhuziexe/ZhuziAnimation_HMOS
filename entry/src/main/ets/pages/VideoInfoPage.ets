import router from '@ohos.router';
import { FFprobeResult, FfprobeStream } from '../common/ffmpegType';
import pasteboard from '@ohos.pasteboard';
import promptAction from '@ohos.promptAction';

@Entry
@Component
struct VideoInfoPage {
  @State videoinfo: FFprobeResult | null = null;

  aboutToAppear() {
    const params = router.getParams() as Record<string, string>;
    if (params && params.videoInfo) {
      try {
        this.videoinfo = JSON.parse(params.videoInfo) as FFprobeResult;
      } catch (e) {
        console.error('解析视频信息失败', e);
        this.videoinfo = null;
      }
    }
  }

  async handleBack() {
    router.back();
  }

  @Builder
  buildTopBar() {
    Row() {
      Button() {
        SymbolGlyph($r('sys.symbol.arrow_left'))
          .fontSize(24)
          .width(24)
          .height(24)
          .fontColor([$r('sys.color.font_primary')])
      }
      .onClick(() => {
        this.handleBack();
      })
      .height(40)
      .width(40)
      .buttonStyle(ButtonStyleMode.TEXTUAL)

      Text('视频属性')
        .layoutWeight(1)
        .fontSize(18)
        .fontColor($r('sys.color.font_primary'))
        .fontWeight(FontWeight.Medium)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .backgroundColor($r('sys.color.background_primary'))
    .shadow({ radius: 2, color: '#1A000000', offsetY: 1 })
  }

  // 文件信息卡片
  @Builder
  buildFileInfo() {
    Column() {
      Text('文件信息')
        .fontSize(22) // 增大字号
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .padding({ bottom: 8 })
      Divider().color($r('sys.color.background_fourth'))
      this.buildInfoRow('文件名', this.videoinfo?.filename ?? '')
      this.buildInfoRow('格式', this.videoinfo?.format ?? '')
      this.buildInfoRow('详细格式', this.videoinfo?.longFormat ?? '')
      this.buildInfoRow('大小', this.videoinfo?.size ?? '')
      this.buildInfoRow('时长', this.videoinfo?.duration ?? '')
      this.buildInfoRow('比特率', this.videoinfo?.bitrate ?? '')
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('sys.color.background_primary'))
    .borderRadius(8)
    .margin({ bottom: 12 })
  }

  // 键值对行（带复制按钮）
  @Builder
  buildInfoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(20) // 增大字号
        .fontColor($r('sys.color.font_secondary'))
        .width('28%') // 稍缩窄
        .flexShrink(0)
      Text(value)
        .fontSize(20) // 增大字号
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)
        .textAlign(TextAlign.Start) // 左对齐
        .wordBreak(WordBreak.BREAK_ALL)
      Button() {
        SymbolGlyph($r('sys.symbol.doc_filled_on_doc'))
          .fontSize(24)
          .width(24)
          .height(24)
          .fontColor([$r('sys.color.font_secondary')])
      }
      .width(40)
      .height(40)
      .buttonStyle(ButtonStyleMode.TEXTUAL)
      .onClick(() => {
        if (!value) return;
        const pasteData = pasteboard.createPlainTextData(value);
        const systemPasteboard = pasteboard.getSystemPasteboard();
        systemPasteboard.setData(pasteData, (err) => {
          if (err) {
            console.error('复制失败:', err);
          } else {
            promptAction.showToast({ message: '已复制到剪贴板' });
          }
        });
      })
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 }) // 增加行间距
    .alignItems(VerticalAlign.Center)
  }

  // 所有流信息
  @Builder
  buildStreams() {
    if (!this.videoinfo) {
      // 无操作
    } else {
      Column() {
        Text('流信息')
          .fontSize(22) // 增大字号
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
          .padding({ bottom: 8 })
        Divider().color($r('sys.color.background_fourth'))
        ForEach(this.videoinfo.allProperties.streams, (stream: FfprobeStream, index: number) => {
          this.buildStreamItem(stream)
        }, (stream: FfprobeStream, index: number) => index.toString())
      }
      .width('100%')
      .padding(12)
      .backgroundColor($r('sys.color.background_primary'))
      .borderRadius(8)
      .margin({ bottom: 12 })
    }
  }

  // 单个流卡片
  @Builder
  buildStreamItem(stream: FfprobeStream) {
    Column() {
      Text(`流 #${stream.index} (${stream.codec_type})`)
        .fontSize(20) // 稍增大
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .padding({ bottom: 4 })
      this.buildInfoRow('编码', stream.codec_name ?? '')
      this.buildInfoRow('编码全称', stream.codec_long_name ?? '')
      if (stream.profile) {
        this.buildInfoRow('Profile', stream.profile)
      }
      if (stream.codec_type === 'video') {
        if (stream.width && stream.height) {
          this.buildInfoRow('分辨率', `${stream.width} × ${stream.height}`)
        }
        if (stream.pix_fmt) {
          this.buildInfoRow('像素格式', stream.pix_fmt)
        }
        if (stream.r_frame_rate) {
          this.buildInfoRow('帧率', stream.r_frame_rate)
        }
        if (stream.bit_rate) {
          this.buildInfoRow('比特率', stream.bit_rate)
        }
        if (stream.nb_frames) {
          this.buildInfoRow('帧数', stream.nb_frames)
        }
      } else if (stream.codec_type === 'audio') {
        if (stream.bit_rate) {
          this.buildInfoRow('比特率', stream.bit_rate)
        }
        if (stream.duration) {
          this.buildInfoRow('时长', stream.duration)
        }
        // 音频特有信息通常从 tags 中获取
      }
      // 展示该流的所有标签
      if (stream.tags && Object.keys(stream.tags).length > 0) {
        Text('标签')
          .fontSize(20) // 略增大
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .padding({ top: 4, bottom: 2 })
        ForEach(Object.keys(stream.tags), (key: string) => {
          this.buildInfoRow(key, stream.tags[key] ?? '')
        }, (key: string) => key)
      }
    }
    .width('100%')
    .padding(8)
    .backgroundColor($r('sys.color.background_secondary'))
    .borderRadius(6)
    .margin({ bottom: 8 })
  }

  // 顶层元数据（格式标签）
  @Builder
  buildTags() {
    if (!this.videoinfo || !this.videoinfo.tags || Object.keys(this.videoinfo.tags).length === 0) {
      // 无内容
    } else {
      Column() {
        Text('元数据')
          .fontSize(22) // 增大字号
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
          .padding({ bottom: 8 })
        Divider().color($r('sys.color.background_fourth'))
        ForEach(Object.keys(this.videoinfo.tags), (key: string) => {
          this.buildInfoRow(key, this.videoinfo!.tags[key] ?? '')
        }, (key: string) => key)
      }
      .width('100%')
      .padding(12)
      .backgroundColor($r('sys.color.background_primary'))
      .borderRadius(8)
      .margin({ bottom: 12 })
    }
  }

  build() {
    Column() {
      this.buildTopBar();
      if (this.videoinfo) {
        Scroll() {
          Column() {
            this.buildFileInfo();
            this.buildStreams();
            this.buildTags();
          }
          .padding({ left: 16, right: 16, bottom: 16 })
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .align(Alignment.Top)
        .contentStartOffset(12)
      } else {
        Text('获取失败')
          .layoutWeight(1)
          .fontSize(22)
          .fontColor($r('sys.color.font_secondary'))
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_tertiary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}