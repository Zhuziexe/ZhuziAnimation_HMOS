import { getMediaFileInfo, getMediaFileInfoSync, MediaInformation, FFmpegKitError,
  CommandSyncResult, executeCommandSync } from '@tyousan/ffmpeg';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { FFprobeResult } from './ffmpegType';

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
 */
async function copyMediaUriToAppSandbox(mediaUri: string, context: common.UIAbilityContext): Promise<string> {
  const srcFd = fs.openSync(mediaUri, fs.OpenMode.READ_ONLY);
  if (srcFd.fd < 0) {
    throw new Error("打开媒体文件失败");
  }

  const tempFileName = `tmp_ffprobe_video.mp4`;
  const tempDestPath = `${context.cacheDir}/${tempFileName}`;

  const destFd = fs.openSync(tempDestPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);

  try {
    const bufferSize = 1024 * 1024;
    const buf = new ArrayBuffer(bufferSize);
    let readLen: number;
    while ((readLen = fs.readSync(srcFd.fd, buf)) > 0) {
      fs.writeSync(destFd.fd, buf, { length: readLen });
    }
    console.info("复制完成，ffmpeg可用路径:", tempDestPath);
    return tempDestPath;
  } finally {
    fs.closeSync(srcFd);
    fs.closeSync(destFd);
  }
}

export async function getVideoInfo(fileURI: string, ctx: common.UIAbilityContext): Promise<FFprobeResult | null> {
  const mediaUri = fileURI;
  const realLocalPath = await copyMediaUriToAppSandbox(mediaUri, ctx);

  try {
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

    try { fs.unlinkSync(realLocalPath); } catch {}
    return result;
  } catch (e) {
    console.warn('错误: ' + JSON.stringify(e));
    try { fs.unlinkSync(realLocalPath); } catch {}
    return null;
  }
}

/**
 * 将视频转换为 GIF
 * @param fileURI 媒体库 URI
 * @param ctx UIAbilityContext
 * @param maxFPS 最大帧率
 * @param maxWidth 最大宽度
 * @param maxVideoLength 最大时长（秒）
 * @param doTwoSteps true: 两步法（调色板优化）
 * @returns GIF 文件在沙箱中的路径，失败返回 null
 */
export async function VideoToGIF(
  fileURI: string,
  ctx: common.UIAbilityContext,
  maxFPS: number,
  maxWidth: number,
  maxVideoLength: number,
  doTwoSteps: boolean
): Promise<string | null> {
  const fps = Math.min(Math.max(maxFPS, 1), 30);
  const width = Math.max(maxWidth, 32);
  const length = Math.max(maxVideoLength, 0.5);

  let inputPath: string;
  try {
    inputPath = await copyMediaUriToAppSandbox(fileURI, ctx);
  } catch (e) {
    console.error('复制媒体文件失败:', e);
    return null;
  }

  // ✅ 固定文件名，无时间戳（每次转换覆盖）
  const outputPath = `${ctx.cacheDir}/output.gif`;
  const palettePath = `${ctx.cacheDir}/palette.png`;

  // 预删除旧文件
  try { fs.unlinkSync(outputPath); } catch {}
  try { fs.unlinkSync(palettePath); } catch {}

  try {
    const filterStr = `fps=${fps},scale=${width}:-1:flags=lanczos`;

    if (doTwoSteps) {
      // 生成调色板
      const paletteArgs = [
        '-ss', '0',
        '-t', String(length),
        '-i', `"${inputPath}"`,
        '-vf', `${filterStr},palettegen`,
        '-y', `"${palettePath}"`
      ];
      const paletteCmd = paletteArgs.join(' ');
      const paletteResult: CommandSyncResult = executeCommandSync(paletteCmd);
      if (paletteResult.evenType !== 'onSuccess') {
        throw new Error(`生成调色板失败: ${paletteResult.failStackTrace || '未知错误'}`);
      }

      // 应用调色板
      const gifArgs = [
        '-ss', '0',
        '-t', String(length),
        '-i', `"${inputPath}"`,
        '-i', `"${palettePath}"`,
        '-filter_complex', `${filterStr}[x];[x][1:v]paletteuse`,
        '-y', `"${outputPath}"`
      ];
      const gifCmd = gifArgs.join(' ');
      const gifResult: CommandSyncResult = executeCommandSync(gifCmd);
      if (gifResult.evenType !== 'onSuccess') {
        throw new Error(`生成 GIF 失败: ${gifResult.failStackTrace || '未知错误'}`);
      }
    } else {
      // 一步法
      const args = [
        '-ss', '0',
        '-t', String(length),
        '-i', `"${inputPath}"`,
        '-vf', filterStr,
        '-y', `"${outputPath}"`
      ];
      const cmd = args.join(' ');
      const result: CommandSyncResult = executeCommandSync(cmd);
      if (result.evenType !== 'onSuccess') {
        throw new Error(`GIF 生成失败: ${result.failStackTrace || '未知错误'}`);
      }
    }

    // 清理临时文件（输入副本和调色板）
    try { fs.unlinkSync(inputPath); } catch {}
    try { fs.unlinkSync(palettePath); } catch {}

    console.info(`GIF 生成成功: ${outputPath}`);
    return outputPath;
  } catch (err) {
    console.error('VideoToGIF 执行异常:', err);
    try { fs.unlinkSync(inputPath); } catch {}
    try { fs.unlinkSync(palettePath); } catch {}
    try { fs.unlinkSync(outputPath); } catch {}
    return null;
  }
}