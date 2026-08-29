import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { TempFileManager } from './TempFileManager';

export class ImageUtils {
  static async loadAndSaveTemp(
    uri: string,
    targetWidth: number,
    targetHeight: number,
    index: number
  ): Promise<string | null> {
    try {
      // 1. 读取原始图片数据
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(file.fd);
      const buffer = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, buffer);
      fileIo.closeSync(file);

      const imageSource = image.createImageSource(buffer);
      const pixelMap = await imageSource.createPixelMap();
      if (!pixelMap) {
        console.error('创建 PixelMap 失败');
        return null;
      }

      const info = pixelMap.getImageInfoSync();
      const srcW = info.size.width;
      const srcH = info.size.height;
      console.info(`原图尺寸: ${srcW}x${srcH}`);

      // 2. 计算 FIT 缩放比例（取较小值）
      const scaleX = targetWidth / srcW;
      const scaleY = targetHeight / srcH;
      const scale = Math.min(scaleX, scaleY);
      let newW = Math.round(srcW * scale);
      let newH = Math.round(srcH * scale);
      newW = Math.max(1, newW);
      newH = Math.max(1, newH);
      console.info(`缩放后尺寸: ${newW}x${newH}，目标: ${targetWidth}x${targetHeight}`);

      // 3. 缩放图片
      await pixelMap.scale(newW, newH);

      // 4. 读取缩放后的像素数据（使用 PositionArea）
      const srcPixelBytes = newW * newH * 4;
      const srcBuffer = new ArrayBuffer(srcPixelBytes);
      const positionArea: image.PositionArea = {
        pixels: srcBuffer,
        offset: 0,
        stride: newW * 4,
        region: {
          size: { width: newW, height: newH },
          x: 0,
          y: 0
        }
      };
      try {
        await pixelMap.readPixels(positionArea);
      } catch (readErr) {
        console.error('readPixels 失败，跳过此图片:', readErr);
        return null;
      }

      // 5. 创建目标画布（全黑，Alpha 设为 255）
      const totalPixels = targetWidth * targetHeight * 4;
      const canvasBuffer = new ArrayBuffer(totalPixels);
      const canvasView = new Uint8Array(canvasBuffer);
      for (let i = 3; i < totalPixels; i += 4) {
        canvasView[i] = 255;
      }

      // 6. 将缩放后的像素复制到画布中央
      const srcBytes = new Uint8Array(srcBuffer);
      const srcRowBytes = newW * 4;
      const dstRowBytes = targetWidth * 4;
      const offsetX = Math.floor((targetWidth - newW) / 2);
      const offsetY = Math.floor((targetHeight - newH) / 2);

      for (let row = 0; row < newH; row++) {
        const srcStart = row * srcRowBytes;
        const dstStart = (offsetY + row) * dstRowBytes + offsetX * 4;
        canvasView.set(srcBytes.subarray(srcStart, srcStart + srcRowBytes), dstStart);
      }

      // 7. 从 canvasBuffer 创建最终的 PixelMap
      const finalPixelMap = await image.createPixelMap(
        canvasBuffer,
        {
          size: { width: targetWidth, height: targetHeight },
          pixelFormat: image.PixelMapFormat.RGBA_8888,
          editable: false,
        }
      );
      if (!finalPixelMap) {
        console.error('创建最终 PixelMap 失败');
        return null;
      }

      // 8. 打包为 PNG
      const imagePacker = image.createImagePacker();
      const packOpts: image.PackingOption = {
        format: 'image/png',
        quality: 100,
      };
      const pngData: ArrayBuffer = await imagePacker.packing(finalPixelMap, packOpts);

      // 9. 确保目录存在并写入临时文件
      TempFileManager.ensureEditorFramesDir();  // <--- 关键修复
      const tempPath = TempFileManager.getFrameFilePath(index);
      const tmpFile = fileIo.openSync(
        tempPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC
      );
      fileIo.writeSync(tmpFile.fd, pngData);
      fileIo.closeSync(tmpFile);

      return `file://${tempPath}`;
    } catch (e) {
      console.error('处理图片失败:', e);
      return null;
    }
  }
}