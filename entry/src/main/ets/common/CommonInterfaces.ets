export interface RenderRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface PixelPos {
  x: number;
  y: number;
}

export interface FfmpegResult {
  sessionId?: number;
}

export interface FfmpegError {
  sessionId?: number;
  errCode?: number | string;
  message?: string;
  stderr?: string;
}