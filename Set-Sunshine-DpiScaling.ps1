<#
.SYNOPSIS
    Parsec仮想ディスプレイのWindows拡大率を100%に設定する。
.DESCRIPTION
    keepでは変更しない。100ではParsec VDDの仮想画面だけを識別して100%に変更する。
.PARAMETER Mode
    keep（既定）または100。
.PARAMETER ShowHelp
    ヘルプを表示する。-h / -help に対応。
.EXAMPLE
    .\Set-Sunshine-DpiScaling.ps1 -Mode 100
.EXAMPLE
    .\Set-Sunshine-DpiScaling.ps1 -Mode keep
.EXAMPLE
    .\Set-Sunshine-DpiScaling.ps1 -h
.NOTES
    非公開のWindows DisplayConfig拡大率APIを使用する。
    モニター識別が曖昧な場合は物理ディスプレイを変更せず中止する。
#>
[CmdletBinding()]
param(
    [ValidateSet('keep', '100')]
    [string]$Mode = 'keep',
    [Alias('h', 'help')]
    [switch]$ShowHelp
)

#region Options
if ($ShowHelp) {
    Get-Help -Name $PSCommandPath -Full
    return
}
if ($Mode -eq 'keep') {
    return
}
$ErrorActionPreference = 'Stop'
#endregion Options

#region ParsecMonitorDpiInterop
if (-not ('ParsecMonitorDpiInterop' -as [type])) {
    $source = @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class ParsecMonitorDpiInterop
{
    private const uint QDC_ONLY_ACTIVE_PATHS = 2;
    private const int ERROR_INSUFFICIENT_BUFFER = 122;
    private const int DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME = 2;
    private const int DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE = -3;
    private const int DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE = -4;

    [StructLayout(LayoutKind.Sequential)]
    private struct LUID { public uint LowPart; public int HighPart; }

    [StructLayout(LayoutKind.Sequential)]
    private struct SourceInfo
    {
        public LUID AdapterId;
        public uint Id;
        public uint ModeInfoIdx;
        public uint StatusFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Rational { public uint Numerator; public uint Denominator; }

    [StructLayout(LayoutKind.Sequential)]
    private struct TargetInfo
    {
        public LUID AdapterId;
        public uint Id;
        public uint ModeInfoIdx;
        public uint OutputTechnology;
        public uint Rotation;
        public uint Scaling;
        public Rational RefreshRate;
        public uint ScanLineOrdering;
        [MarshalAs(UnmanagedType.Bool)] public bool TargetAvailable;
        public uint StatusFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct PathInfo
    {
        public SourceInfo Source;
        public TargetInfo Target;
        public uint Flags;
    }

    [StructLayout(LayoutKind.Sequential, Size = 64)]
    private struct ModeInfo
    {
        public uint InfoType;
        public uint Id;
        public LUID AdapterId;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct DeviceInfoHeader
    {
        public int Type;
        public uint Size;
        public LUID AdapterId;
        public uint Id;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct TargetDeviceName
    {
        public DeviceInfoHeader Header;
        public uint Flags;
        public uint OutputTechnology;
        public ushort EdidManufactureId;
        public ushort EdidProductCodeId;
        public uint ConnectorInstance;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)]
        public string MonitorFriendlyDeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string MonitorDevicePath;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SourceDpiScaleGet
    {
        public DeviceInfoHeader Header;
        public int MinimumRelative;
        public int CurrentRelative;
        public int MaximumRelative;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SourceDpiScaleSet
    {
        public DeviceInfoHeader Header;
        public int ScaleRelative;
    }

    [DllImport("user32.dll")]
    private static extern int GetDisplayConfigBufferSizes(uint flags, out uint pathCount, out uint modeCount);

    [DllImport("user32.dll")]
    private static extern int QueryDisplayConfig(uint flags, ref uint pathCount,
        [Out] PathInfo[] paths, ref uint modeCount, [Out] ModeInfo[] modes, IntPtr topologyId);

    [DllImport("user32.dll", EntryPoint = "DisplayConfigGetDeviceInfo")]
    private static extern int GetTargetDeviceInfo(ref TargetDeviceName request);

    [DllImport("user32.dll", EntryPoint = "DisplayConfigGetDeviceInfo")]
    private static extern int GetSourceDpiInfo(ref SourceDpiScaleGet request);

    [DllImport("user32.dll", EntryPoint = "DisplayConfigSetDeviceInfo")]
    private static extern int SetSourceDpiInfo(ref SourceDpiScaleSet request);

    private static PathInfo[] ActivePaths()
    {
        for (int i = 0; i < 3; ++i)
        {
            uint pathsCount;
            uint modesCount;
            int rc = GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, out pathsCount, out modesCount);
            if (rc != 0)
                throw new Win32Exception(rc, "アクティブな画面を列挙できない");
            PathInfo[] paths = new PathInfo[pathsCount];
            ModeInfo[] modes = new ModeInfo[modesCount];
            rc = QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, ref pathsCount, paths,
                ref modesCount, modes, IntPtr.Zero);
            if (rc == ERROR_INSUFFICIENT_BUFFER)
                continue;
            if (rc != 0)
                throw new Win32Exception(rc, "画面構成を取得できない");
            Array.Resize(ref paths, (int)pathsCount);
            return paths;
        }
        throw new InvalidOperationException("画面構成が切り替わっているため列挙できない");
    }

    private static bool IsParsecDisplay(TargetInfo target)
    {
        TargetDeviceName name = new TargetDeviceName();
        name.Header.Type = DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME;
        name.Header.Size = (uint)Marshal.SizeOf(typeof(TargetDeviceName));
        name.Header.AdapterId = target.AdapterId;
        name.Header.Id = target.Id;
        if (GetTargetDeviceInfo(ref name) != 0)
            return false;
        // Require the Parsec VDD display ID/name. Never fall back to the primary monitor.
        return (!String.IsNullOrEmpty(name.MonitorDevicePath) &&
            name.MonitorDevicePath.IndexOf("PSCCDD0", StringComparison.OrdinalIgnoreCase) >= 0) ||
            String.Equals(name.MonitorFriendlyDeviceName, "ParsecVDA", StringComparison.OrdinalIgnoreCase);
    }

    public static string Enforce100()
    {
        if (Marshal.SizeOf(typeof(PathInfo)) != 72 ||
            Marshal.SizeOf(typeof(TargetDeviceName)) != 420 ||
            Marshal.SizeOf(typeof(SourceDpiScaleGet)) != 32 ||
            Marshal.SizeOf(typeof(SourceDpiScaleSet)) != 24)
            throw new InvalidOperationException("Windows画面構造体のサイズが想定と異なる");

        List<PathInfo> matches = new List<PathInfo>();
        foreach (PathInfo path in ActivePaths())
        {
            if (IsParsecDisplay(path.Target))
                matches.Add(path);
        }
        if (matches.Count == 0)
            return "not-found";
        if (matches.Count != 1)
            throw new InvalidOperationException("Parsec仮想画面が複数見つかったため操作を中止した");

        SourceInfo source = matches[0].Source;
        SourceDpiScaleGet dpi = new SourceDpiScaleGet();
        dpi.Header.Type = DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE;
        dpi.Header.Size = (uint)Marshal.SizeOf(typeof(SourceDpiScaleGet));
        dpi.Header.AdapterId = source.AdapterId;
        dpi.Header.Id = source.Id;
        int result = GetSourceDpiInfo(ref dpi);
        if (result != 0)
            throw new Win32Exception(result, "Windowsの拡大率取得に失敗した");
        if (dpi.MinimumRelative > 0 || dpi.MinimumRelative < -11 ||
            dpi.CurrentRelative < dpi.MinimumRelative || dpi.CurrentRelative > dpi.MaximumRelative)
            throw new InvalidOperationException("Windowsの拡大率情報が不正なため変更を中止した");
        if (dpi.CurrentRelative == dpi.MinimumRelative)
            return "already-100";

        SourceDpiScaleSet set = new SourceDpiScaleSet();
        set.Header.Type = DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE;
        set.Header.Size = (uint)Marshal.SizeOf(typeof(SourceDpiScaleSet));
        set.Header.AdapterId = source.AdapterId;
        set.Header.Id = source.Id;
        set.ScaleRelative = dpi.MinimumRelative;
        result = SetSourceDpiInfo(ref set);
        if (result != 0)
            throw new Win32Exception(result, "Windowsの100%拡大率設定に失敗した");
        return "changed-to-100";
    }
}
'@
    Add-Type -TypeDefinition $source -Language CSharp -ReferencedAssemblies @('System.dll')
}
#endregion ParsecMonitorDpiInterop

#region ApplyDpi
[ParsecMonitorDpiInterop]::Enforce100()
#endregion ApplyDpi