import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { FrameData } from '../model/FrameData';

export interface LoadZapResult {
  frames: FrameData[];
  fps: number;
  ratioIndex: number;
}

export class ZapUtils {
  private static context: common.UIAbilityContext;

  static init(context: common.UIAbilityContext) {
    ZapUtils.context = context;
    try {
      const dir = context.filesDir + '/temp';
      fileIo.mkdirSync(dir);
    } catch (e) {}
  }

  static async saveZap(
    filePath: string,
    frames: FrameData[],
    fps: number,
    ratioIndex: number
  ): Promise<boolean> {
    if (frames.length === 0) return false;
    try {
      const file = fileIo.openSync(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);

      // 写入文件头
      const magic = new Uint8Array([0x5A, 0x41, 0x50, 0x31]);
      const version = new Uint8Array([0x01, 0x00]);
      const fpsBytes = new Uint8Array([fps & 0xFF, (fps >> 8) & 0xFF]);
      const frameCount = new Uint32Array([frames.length]);
      const ratioByte = new Uint8Array([ratioIndex]);

      fileIo.writeSync(file.fd, magic.buffer);
      fileIo.writeSync(file.fd, version.buffer);
      fileIo.writeSync(file.fd, fpsBytes.buffer);
      fileIo.writeSync(file.fd, frameCount.buffer);
      fileIo.writeSync(file.fd, ratioByte.buffer);

      // 预留表空间
      const tableSize = frames.length * 2 * 4;
      const placeholder = new Uint8Array(tableSize);
      fileIo.writeSync(file.fd, placeholder.buffer);

      const tableOffset = 4 + 2 + 2 + 4 + 1; // 13
      let currentOffset = tableOffset + tableSize;
      const offsets: number[] = [];
      const sizes: number[] = [];

      // 写入帧数据
      for (let i = 0; i < frames.length; i++) {
        const frame = frames[i];
        if (!frame.uri) {
          offsets.push(0);
          sizes.push(0);
          continue;
        }
        const pixelMap = await ZapUtils.loadPixelMap(frame.uri);
        if (!pixelMap) {
          offsets.push(0);
          sizes.push(0);
          continue;
        }
        const packer = image.createImagePacker();
        const packOpts: image.PackingOption = {
          format: 'image/png',
          quality: 100,
        };
        const pngData = await packer.packing(pixelMap, packOpts);
        if (!pngData || pngData.byteLength === 0) {
          offsets.push(0);
          sizes.push(0);
          continue;
        }
        offsets.push(currentOffset);
        sizes.push(pngData.byteLength);
        fileIo.writeSync(file.fd, pngData);
        currentOffset += pngData.byteLength;
        console.info(`帧 ${i} 写入偏移: ${offsets[i]}, 大小: ${sizes[i]}`);
      }

      // 回填表：先移动文件指针到表头，再写入
      fileIo.lseek(file.fd, tableOffset, 0); // SEEK_SET
      const offsetBuffer = new Uint32Array(offsets);
      const sizeBuffer = new Uint32Array(sizes);
      const tableData = new Uint8Array(offsets.length * 4 + sizes.length * 4);
      tableData.set(new Uint8Array(offsetBuffer.buffer), 0);
      tableData.set(new Uint8Array(sizeBuffer.buffer), offsets.length * 4);
      fileIo.writeSync(file.fd, tableData.buffer);

      fileIo.closeSync(file);
      console.info('ZAP 保存成功');
      return true;
    } catch (e) {
      console.error('保存ZAP失败:', e);
      return false;
    }
  }

  static async loadZap(filePath: string): Promise<LoadZapResult | null> {
    try {
      const file = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(file.fd);
      const buffer = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, buffer);
      fileIo.closeSync(file);

      const view = new DataView(buffer);
      let offset = 0;

      const magic = new Uint8Array(buffer, offset, 4);
      if (magic[0] !== 0x5A || magic[1] !== 0x41 || magic[2] !== 0x50 || magic[3] !== 0x31) {
        console.error('无效的ZAP文件: 魔数错误');
        return null;
      }
      offset += 4;

      const version = view.getUint16(offset, true);
      if (version !== 1) {
        console.error('不支持的版本:', version);
        return null;
      }
      offset += 2;

      const fps = view.getUint16(offset, true);
      offset += 2;

      const frameCount = view.getUint32(offset, true);
      offset += 4;

      const ratioIndex = view.getUint8(offset);
      offset += 1;

      console.info(`ZAP信息: 帧率=${fps}, 帧数=${frameCount}, 比例=${ratioIndex}`);

      const tableSize = frameCount * 2 * 4;
      const tableBuffer = buffer.slice(offset, offset + tableSize);
      const tableView = new DataView(tableBuffer);
      const offsets: number[] = [];
      const sizes: number[] = [];
      for (let i = 0; i < frameCount; i++) {
        offsets.push(tableView.getUint32(i * 4, true));
        sizes.push(tableView.getUint32((i + frameCount) * 4, true));
      }
      offset += tableSize;

      const frames: FrameData[] = [];
      for (let i = 0; i < frameCount; i++) {
        if (sizes[i] === 0 || offsets[i] === 0) continue;
        // 计算 PNG 数据偏移
        const pngStart = offset + offsets[i] - (offset);
        const pngEnd = pngStart + sizes[i];
        if (pngEnd > buffer.byteLength) {
          console.error(`帧 ${i} 数据超出范围`);
          continue;
        }
        const pngData = buffer.slice(pngStart, pngEnd);
        // 转换为 ArrayBuffer
        const arrayBuffer = pngData;
        console.info(`帧 ${i} PNG数据大小: ${arrayBuffer.byteLength}`);
        const imageSource = image.createImageSource(arrayBuffer);
        if (!imageSource) {
          console.error(`帧 ${i} 创建ImageSource失败`);
          continue;
        }
        const pixelMap = await imageSource.createPixelMap();
        if (!pixelMap) {
          console.error(`帧 ${i} 创建PixelMap失败`);
          continue;
        }

        const tempDir = ZapUtils.context.filesDir + '/temp';
        const tempPath = `${tempDir}/frame_${Date.now()}_${i}.png`;
        const packer = image.createImagePacker();
        const pngData2 = await packer.packing(pixelMap, { format: 'image/png', quality: 100 });
        const file2 = fileIo.openSync(tempPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
        fileIo.writeSync(file2.fd, pngData2);
        fileIo.closeSync(file2);

        const frame: FrameData = {
          id: `${i}_${Date.now()}`,
          uri: `file://${tempPath}`
        };
        frames.push(frame);
      }

      if (frames.length === 0) {
        console.error('没有成功加载任何帧');
        return null;
      }

      const result: LoadZapResult = {
        frames: frames,
        fps: fps,
        ratioIndex: ratioIndex
      };
      console.info(`ZAP加载成功: ${frames.length} 帧`);
      return result;
    } catch (e) {
      console.error('加载ZAP失败:', e);
      return null;
    }
  }

  private static async loadPixelMap(uri: string): Promise<image.PixelMap | null> {
    try {
      const filePath = uri.startsWith('file://') ? uri.substring(7) : uri;
      const file = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(file.fd);
      const buffer = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, buffer);
      fileIo.closeSync(file);
      const imageSource = image.createImageSource(buffer);
      if (!imageSource) return null;
      return await imageSource.createPixelMap();
    } catch (e) {
      console.error('loadPixelMap失败:', e);
      return null;
    }
  }
}