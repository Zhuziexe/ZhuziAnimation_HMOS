@Component
export struct HomeContent {
  @StorageLink('tabindex') tabindex: number = 1;

  private getGreeting(): string {
    const hour = new Date().getHours();
    if (hour < 6) return '🌃 夜深了';
    if (hour < 12) return '☀️ 早上好';
    if (hour < 18) return '🌥️ 下午好';
    if (hour < 22) return '🌙 晚上好';
    return '🌃 夜深了';
  }

  goToTools(): void {
    this.tabindex = 0;
  }

  goToProjects(): void {
    this.tabindex = 2;
  }

  build() {
    Stack() {
      Scroll() {
        Column({ space: 12 }) {
          Text(this.getGreeting())
            .padding({left:8,right:8})
            .width('100%')
            .fontSize(32)
            .fontColor($r('sys.color.font_primary'))
            .fontWeight(FontWeight.Bold)

          this.buildCard(
            '🎬',
            '视频工具',
            '裁剪、GIF、水印、模糊...',
            () => this.goToTools()
          )

          this.buildCard(
            '🎞️',
            '定格动画',
            '制作定格动画',
            () => this.goToProjects()
          )
        }
        .width('100%')
        .padding({ left: 20, right: 20 })
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .contentStartOffset(56)
      .contentEndOffset(80)

      Row() {
        Text($r('app.string.EntryAbility_label'))
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

  @Builder
  buildCard(emoji: string, title: string, subtitle: string, action: () => void) {
    Row() {
      Text(emoji)
        .fontSize(48)
        .margin({ right: 20 })

      Column() {
        Text(title)
          .fontSize(24)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .textAlign(TextAlign.Start)
          .width('100%')
        Text(subtitle)
          .fontSize(16)
          .fontColor($r('sys.color.font_primary'))
          .textAlign(TextAlign.Start)
          .width('100%')
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(120)
    .padding({ left: 24, right: 20 })
    .linearGradient({
      angle: 135,
      colors: [
        [$r('app.color.home_card_1'), 0.0],
        [$r('app.color.home_card_2'), 0.5],
        [$r('app.color.home_card_3'), 1.0]
      ]
    })
    .border({ width: 1, color: 'rgba(255,255,255,0.25)', radius: 20 })
    .shadow({
      radius: 30,
      color: 'rgba(79, 172, 254, 0.35)',
      offsetY: 10
    })
    .borderRadius(20)
    .onClick(action)
  }
}