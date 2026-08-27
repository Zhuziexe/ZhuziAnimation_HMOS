import { getMediaFileInfo, getMediaFileInfoSync, MediaInformation, FFmpegKitError } from '@tyousan/ffmpeg';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { FFprobeResult } from './ffmpegType';

// 视频信息结构
export interface VideoInfo {
  duration?: string;
  width?: number;
  height?: number;
  fps?: number;
  bitrate?: string;
  formatName?: string;
}

/**
 * 将 file://media/xxx 媒体uri复制到应用缓存目录，返回可供ffmpeg使用的真实沙箱路径
 * @param mediaUri 例如 file://media/Photo/15/VID_1787659537_008/Zhuzi_1787659434674.mp4
 * @param context UIAbilityContext
 * @returns 复制后的沙箱真实路径，如 /data/storage/el2/base/cache/tmp_video_xxx.mp4
 */
async function copyMediaUriToAppSandbox(mediaUri: string, context: common.UIAbilityContext): Promise<string> {
  // 1.打开媒体uri，拿到文件描述符fd
  const srcFd = fs.openSync(mediaUri, fs.OpenMode.READ_ONLY);
  if (srcFd.fd < 0) {
    throw new Error("打开媒体文件失败");
  }

  // 2.生成临时文件路径，放在cache目录
  const tempFileName = `tmp_ffprobe_video.mp4`;
  const tempDestPath = `${context.cacheDir}/${tempFileName}`;

  // 创建目标临时文件
  const destFd = fs.openSync(tempDestPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);

  try {
    // 3.流拷贝
    const bufferSize = 1024 * 1024;
    const buf = new ArrayBuffer(bufferSize);
    let readLen: number;
    while ((readLen = fs.readSync(srcFd.fd, buf)) > 0) {
      fs.writeSync(destFd.fd, buf, { length: readLen });
    }
    console.info("复制完成，ffmpeg可用路径:", tempDestPath);
    return tempDestPath;
  } finally {
    // 务必关闭fd
    fs.closeSync(srcFd);
    fs.closeSync(destFd);
  }
}

// VideoUtils.ets
export async function getVideoInfo(fileURI: string, ctx: common.UIAbilityContext): Promise<FFprobeResult | null> {
  const mediaUri = fileURI;
  const realLocalPath = await copyMediaUriToAppSandbox(mediaUri, ctx);

  try {
    // 包装成 Promise
    const result = await new Promise<FFprobeResult | null>((resolve) => {
      getMediaFileInfo({
        path: realLocalPath,
        success: (a: MediaInformation) => {
          console.info('FFMPEG成功');
          let b = a as FFprobeResult;
          b.filename = fileURI;
          resolve(b);
        },
        fail: (error) => {
          console.warn('FFMPEG错误: ' + JSON.stringify(error));
          resolve(null);
        }
      });
    });

    // 无论成功失败，删除临时文件
    try { fs.unlinkSync(realLocalPath); } catch {}
    return result;
  } catch (e) {
    console.warn('错误: ' + JSON.stringify(e));
    try { fs.unlinkSync(realLocalPath); } catch {}
    return null;
  }
}