// ffmpegType.ets

/** 单个流（视频流/音频流） */
export interface FfprobeStream {
  index: number;
  codec_name: string;
  codec_long_name: string;
  profile: string;
  codec_type: 'video' | 'audio' | string;
  codec_tag_string: string;
  codec_tag: string;
  width?: number;
  height?: number;
  coded_width?: number;
  coded_height?: number;
  pix_fmt?: string;
  level?: number;
  r_frame_rate: string;
  avg_frame_rate: string;
  time_base: string;
  start_pts: number;
  start_time: string;
  duration_ts: number;
  duration: string;
  bit_rate?: string;
  nb_frames?: string;
  disposition: Record<string, number>;
  tags: Record<string, string>;
}

/** format 容器信息 */
export interface FfprobeFormat {
  filename: string;
  nb_streams: number;
  nb_programs: number;
  format_name: string;
  format_long_name: string;
  start_time: string;
  duration: string;
  size: string;
  bit_rate: string;
  probe_score: number;
  tags: Record<string, string>;
}

/** @tyousan/ffmpeg runProbe 封装后的返回结构（就是你打印出来的结构） */
interface FFprobeAllProps {
  streams: FfprobeStream[];
  format: FfprobeFormat;
}

export interface FFprobeResult {
  tags: Record<string, string>;
  allProperties: FFprobeAllProps;
  bitrate: string;
  duration: string;
  filename: string;
  format: string;
  longFormat: string;
  size: string;
}