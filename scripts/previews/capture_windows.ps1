param(
  [Parameter(Mandatory = $true)] [string] $Executable,
  [Parameter(Mandatory = $true)] [string] $Output
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class QingxuPreviewNative {
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extraInfo);
}
'@

function Get-QingxuWindowRect([System.Diagnostics.Process] $Process) {
  $Process.Refresh()
  if ($Process.MainWindowHandle -eq [IntPtr]::Zero) { return $null }
  $rect = New-Object QingxuPreviewNative+RECT
  if (-not [QingxuPreviewNative]::GetWindowRect($Process.MainWindowHandle, [ref]$rect)) { return $null }
  return $rect
}

$process = Start-Process -FilePath $Executable -PassThru
try {
  $deadline = (Get-Date).AddSeconds(25)
  $rect = $null
  while ((Get-Date) -lt $deadline -and $null -eq $rect) {
    Start-Sleep -Milliseconds 500
    $rect = Get-QingxuWindowRect $process
  }
  if ($null -eq $rect) { throw 'Qingxu window was not ready.' }

  Start-Sleep -Seconds 4

  $rect = Get-QingxuWindowRect $process
  if ($null -eq $rect) { throw 'Qingxu window disappeared before capture.' }
  $left = [Math]::Max(0, $rect.Left)
  $top = [Math]::Max(0, $rect.Top)
  $width = [Math]::Max(1, $rect.Right - $rect.Left)
  $height = [Math]::Max(1, $rect.Bottom - $rect.Top)
  $bitmap = New-Object System.Drawing.Bitmap $width, $height
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  try {
    $graphics.CopyFromScreen($left, $top, 0, 0, $bitmap.Size)
    $directory = Split-Path -Parent $Output
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $bitmap.Save($Output, [System.Drawing.Imaging.ImageFormat]::Png)
  } finally {
    $graphics.Dispose()
    $bitmap.Dispose()
  }
} finally {
  if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
}
