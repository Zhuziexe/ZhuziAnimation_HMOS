// common/VideoUtils.ts
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { executeCommand, stopCommand, getMediaFileInfo, MediaInformation } from '@tyousan/ffmpeg';
import { FFprobeResult } from './ffmpegType';   // 请根据实际路径调整

// ---------- 定义返回类型接口（解决 arkts-no-obj-literals-as-types） ----------
export interface GifTaskResult {
  promise: Promise<string | null>;
  cancel: () => void;
}

// ---------- 辅助函数 ----------
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

// ---------- 获取视频信息 ----------
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
        fail: () => { resolve(null); }
      });
    });
    try { fs.unlinkSync(realLocalPath); } catch {}
    return result;
  } catch (e) {
    try { fs.unlinkSync(realLocalPath); } catch {}
    return null;
  }
}

// ---------- 异步 GIF 转换（返回 GifTaskResult） ----------
export function VideoToGIF(
  fileURI: string,
  ctx: common.UIAbilityContext,
  maxFPS: number,
  maxWidth: number,
  maxVideoLength: number,
  doTwoSteps: boolean
): GifTaskResult {
  let sessionId: number = -1;
  let isCancelled = false;

  const cancel = (): void => {
    if (sessionId > 0) {
      stopCommand({ sessionId });
    }
    isCancelled = true;
  };

  const promise = new Promise<string | null>((resolve, reject) => {
    // 将变量声明提升到 try 外部
    let inputPath: string = '';
    let outputPath: string = '';
    let palettePath: string = '';

    const runCommand = (args: string[]): Promise<void> => {
      return new Promise((resolveCmd, rejectCmd) => {
        executeCommand({
          cmd: args.join(' '),
          start: (result) => {
            sessionId = result.sessionId;
          },
          success: () => {
            resolveCmd();
          },
          fail: (error) => {
            rejectCmd(error);
          },
          cancel: () => {
            rejectCmd(new Error('Cancelled'));
          },
          complete: () => {
            // ignore
          }
        });
      });
    };

    (async () => {
      try {
        const fps = Math.min(Math.max(maxFPS, 1), 30);
        const width = Math.max(maxWidth, 32);
        const length = Math.max(maxVideoLength, 0.5);

        const cacheDir = ctx.cacheDir + '/tools/togif/';
        fs.mkdirSync(cacheDir, true);

        inputPath = cacheDir + 'tmp_input.mp4';
        await copyMediaToPath(fileURI, inputPath);

        outputPath = cacheDir + 'output.gif';
        palettePath = cacheDir + 'palette.png';

        try { fs.unlinkSync(outputPath); } catch {}
        try { fs.unlinkSync(palettePath); } catch {}

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
          await runCommand(paletteArgs);
          if (isCancelled) { resolve(null); return; }

          // 生成 GIF
          const gifArgs = [
            '-ss', '0',
            '-t', String(length),
            '-i', `"${inputPath}"`,
            '-i', `"${palettePath}"`,
            '-filter_complex', `${filterStr}[x];[x][1:v]paletteuse`,
            '-y', `"${outputPath}"`
          ];
          await runCommand(gifArgs);
        } else {
          const args = [
            '-ss', '0',
            '-t', String(length),
            '-i', `"${inputPath}"`,
            '-vf', filterStr,
            '-y', `"${outputPath}"`
          ];
          await runCommand(args);
        }

        if (isCancelled) {
          try { fs.unlinkSync(outputPath); } catch {}
          resolve(null);
          return;
        }

        // 清理临时文件
        try { fs.unlinkSync(inputPath); } catch {}
        try { fs.unlinkSync(palettePath); } catch {}

        resolve(outputPath);
      } catch (err) {
        // 清理并拒绝，此时变量已定义
        if (inputPath) {
          try { fs.unlinkSync(inputPath); } catch {}
        }
        if (palettePath) {
          try { fs.unlinkSync(palettePath); } catch {}
        }
        if (outputPath) {
          try { fs.unlinkSync(outputPath); } catch {}
        }
        reject(err);
      }
    })();
  });

  return { promise, cancel };
}