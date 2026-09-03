export function createHueRotationMatrix(angle: number): number[] {
  const rad = angle * Math.PI / 180;
  const cos = Math.cos(rad);
  const sin = Math.sin(rad);

  const lumR = 0.2126;
  const lumG = 0.7152;
  const lumB = 0.0722;

  const m00 = lumR + (1 - lumR) * cos - lumR * sin;
  const m01 = lumG - lumG * cos - lumG * sin;
  const m02 = lumB - lumB * cos + (1 - lumB) * sin;
  const m10 = lumR - lumR * cos + lumR * sin;
  const m11 = lumG + (1 - lumG) * cos - lumG * sin;
  const m12 = lumB - lumB * cos - lumB * sin;
  const m20 = lumR - lumR * cos - (1 - lumR) * sin;
  const m21 = lumG - lumG * cos + (1 - lumG) * sin;
  const m22 = lumB + (1 - lumB) * cos - lumB * sin;

  return [
    m00, m01, m02, 0, 0,
    m10, m11, m12, 0, 0,
    m20, m21, m22, 0, 0,
    0,   0,   0,   1, 0
  ];
}