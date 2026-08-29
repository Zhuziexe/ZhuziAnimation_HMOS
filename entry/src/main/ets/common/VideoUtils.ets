import { getMediaFileInfo, MediaInformation, CommandSyncResult, executeCommandSync } from '@tyousan/ffmpeg';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { FFprobeResult } from './ffmpegType';

// 辅助：复制媒体到指定路径
async function copyMediaToPath(mediaUri: string, destPath: string): Promise<void> {
  const srcFd = fs.openSync(mediaUri, fs.OpenMode.READ_ONLY);
  if (srcFd.fd < 0) throw new Error('打开媒体失败');
  const destFd = fs.openSync(destPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
  try {
    const bufferSize = 1024 * 1024;
    const buf = new ArrayBuffer(bufferSize);
    let readLen: number;
    while ((readLen = fs.readSync(srcFd.fd, buf)) > 0) {
      fs.writeSync(destFd.fd, buf, { length: readLen });
    }
  } finally {
    fs.closeSync(srcFd);
    fs.closeSync(destFd);
  }
}

export async function getVideoInfo(fileURI: string, ctx: common.UIAbilityContext): Promise<FFprobeResult | null> {
  const cacheDir = ctx.cacheDir + '/tools/getinfo/';
  fs.mkdirSync(cacheDir, true);
  const realLocalPath = cacheDir + 'tmp_ffprobe_video.mp4';

  await copyMediaToPath(fileURI, realLocalPath);

  try {
    const result = await new Promise<FFprobeResult | null>((resolve) => {
      getMediaFileInfo({
        path: realLocalPath,
        success: (a: MediaInformation) => {
          let b = a as FFprobeResult;
          b.filename = fileURI;
          resolve(b);
        },
        fail: (error) => { resolve(null); }
      });
    });
    try { fs.unlinkSync(realLocalPath); } catch {}
    return result;
  } catch (e) {
    try { fs.unlinkSync(realLocalPath); } catch {}
    return null;
  }
}

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

  const cacheDir = ctx.cacheDir + '/tools/togif/';
  fs.mkdirSync(cacheDir, true);

  const inputPath = cacheDir + 'tmp_input.mp4';
  await copyMediaToPath(fileURI, inputPath);

  const outputPath = cacheDir + 'output.gif';
  const palettePath = cacheDir + 'palette.png';

  try { fs.unlinkSync(outputPath); } catch {}
  try { fs.unlinkSync(palettePath); } catch {}

  try {
    const filterStr = `fps=${fps},scale=${width}:-1:flags=lanczos`;

    if (doTwoSteps) {
      const paletteArgs = [
        '-ss', '0',
        '-t', String(length),
        '-i', `"${inputPath}"`,
        '-vf', `${filterStr},palettegen`,
        '-y', `"${palettePath}"`
      ];
      const paletteResult: CommandSyncResult = executeCommandSync(paletteArgs.join(' '));
      if (paletteResult.evenType !== 'onSuccess') {
        throw new Error(`生成调色板失败: ${paletteResult.failStackTrace || '未知错误'}`);
      }

      const gifArgs = [
        '-ss', '0',
        '-t', String(length),
        '-i', `"${inputPath}"`,
        '-i', `"${palettePath}"`,
        '-filter_complex', `${filterStr}[x];[x][1:v]paletteuse`,
        '-y', `"${outputPath}"`
      ];
      const gifResult: CommandSyncResult = executeCommandSync(gifArgs.join(' '));
      if (gifResult.evenType !== 'onSuccess') {
        throw new Error(`生成 GIF 失败: ${gifResult.failStackTrace || '未知错误'}`);
      }
    } else {
      const args = [
        '-ss', '0',
        '-t', String(length),
        '-i', `"${inputPath}"`,
        '-vf', filterStr,
        '-y', `"${outputPath}"`
      ];
      const result: CommandSyncResult = executeCommandSync(args.join(' '));
      if (result.evenType !== 'onSuccess') {
        throw new Error(`GIF 生成失败: ${result.failStackTrace || '未知错误'}`);
      }
    }

    try { fs.unlinkSync(inputPath); } catch {}
    try { fs.unlinkSync(palettePath); } catch {}

    console.info(`GIF 生成成功: ${outputPath}`);
    return outputPath;
  } catch (err) {
    console.error('VideoToGIF 异常:', err);
    try { fs.unlinkSync(inputPath); } catch {}
    try { fs.unlinkSync(palettePath); } catch {}
    try { fs.unlinkSync(outputPath); } catch {}
    return null;
  }
}