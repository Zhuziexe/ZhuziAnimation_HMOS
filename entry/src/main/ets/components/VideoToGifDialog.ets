import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { VideoToGIF } from '../common/VideoUtils';

// ---------- 进度弹窗 ----------
@CustomDialog
export struct GifProgressDialog {
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

// ---------- 设置弹窗 ----------
@CustomDialog
export struct GifSettingsDialog {
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
  private taskCancel?: () => void;   // 取消函数

  build() {
    Column({ space: 12 }) {
      Text('视频转GIF')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)

      Row() {
        Text('帧率').width(80)
        Select(this.fpsOptions)
          .value(this.fpsOptions[1].value)
          .selected(1)
          .onSelect((index: number) => {
            this.fps = parseInt(this.fpsOptions[index].value as string, 10);
          })
          .layoutWeight(1)
      }

      Row() {
        Text('宽度').width(80)
        Select(this.widthOptions)
          .value(this.widthOptions[1].value)
          .selected(1)
          .onSelect((index: number) => {
            this.targetWidth = parseInt(this.widthOptions[index].value as string, 10);
          })
          .layoutWeight(1)
      }

      Row() {
        Text('最高时长').width(80)
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
        Text('两步法调色盘').layoutWeight(1)
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
    // 显示进度弹窗
    this.progressDialogController = new CustomDialogController({
      builder: GifProgressDialog({
        cancelCallback: () => {
          this.taskCancel?.();   // 触发取消
        }
      })
    });
    this.progressDialogController.open();

    // 调用异步转换
    const GeneratedDestructObj_1 = VideoToGIF(
      this.videoUri,
      this.context,
      this.fps,
      this.targetWidth,
      this.maxLength,
      this.useTwoSteps
    );
    const promise = GeneratedDestructObj_1.promise;
    const cancel = GeneratedDestructObj_1.cancel;
    this.taskCancel = cancel;

    promise.then((resultPath: string | null) => {
      this.progressDialogController?.close();
      if (resultPath) {
        this.saveToGallery(resultPath);
      } else {
        promptAction.showToast({ message: '转换失败或已取消' });
      }
    }).catch((err: Error) => {
      this.progressDialogController?.close();
      if (err.message === 'Cancelled') {
        promptAction.showToast({ message: '已取消转换' });
      } else {
        promptAction.showToast({ message: '转换异常: ' + err.message });
      }
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