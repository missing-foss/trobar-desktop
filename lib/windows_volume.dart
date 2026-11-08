// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// Windows volume calls through dart:ffi: free/total space of a card, and the
// error mode that keeps an empty drive from raising a system dialog. Only
// dart:ffi, with kernel32's own allocator, so no package is needed for two
// calls. Nothing here may run off Windows: kernel32 is opened on first use.

import 'dart:ffi';

import 'package:flutter/foundation.dart' show visibleForTesting;

typedef _GetDiskFreeSpaceExWNative = Int32 Function(
    Pointer<Uint16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>);
typedef _GetDiskFreeSpaceExWDart = int Function(
    Pointer<Uint16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>);
typedef _LocalAllocNative = Pointer<Void> Function(Uint32, IntPtr);
typedef _LocalAllocDart = Pointer<Void> Function(int, int);
typedef _LocalFreeNative = Pointer<Void> Function(Pointer<Void>);
typedef _LocalFreeDart = Pointer<Void> Function(Pointer<Void>);
typedef _SetErrorModeNative = Uint32 Function(Uint32);
typedef _SetErrorModeDart = int Function(int);
typedef _GetDriveTypeWNative = Uint32 Function(Pointer<Uint16>);
typedef _GetDriveTypeWDart = int Function(Pointer<Uint16>);

// LocalAlloc's GPTR: fixed memory, zeroed.
const _gptr = 0x0040;
// SetErrorMode: no "no disk in drive" box, no file-open error box.
const _semFailCriticalErrors = 0x0001;
const _semNoOpenFileErrorBox = 0x8000;

// GetDriveTypeW: a drive the system reports as removable media (a card
// reader, a USB stick), as opposed to fixed, network, CD-ROM or RAM.
const driveRemovable = 2;

DynamicLibrary? _kernel32Lib;
DynamicLibrary get _kernel32 =>
    _kernel32Lib ??= DynamicLibrary.open('kernel32.dll');

/// [path] as the NUL-terminated UTF-16 a `...W` call takes. A Dart string's
/// code units already are UTF-16, surrogate pairs included.
@visibleForTesting
List<int> utf16z(String path) => [...path.codeUnits, 0];

/// Free bytes available to this user and total bytes of the volume holding
/// [path], or null when Windows can't say (no disk in the drive, no access).
({int free, int total})? windowsVolumeSpace(String path) {
  final alloc = _kernel32
      .lookupFunction<_LocalAllocNative, _LocalAllocDart>('LocalAlloc');
  final free =
      _kernel32.lookupFunction<_LocalFreeNative, _LocalFreeDart>('LocalFree');
  final getSpace = _kernel32
      .lookupFunction<_GetDiskFreeSpaceExWNative, _GetDiskFreeSpaceExWDart>(
          'GetDiskFreeSpaceExW');

  final units = utf16z(path);
  final name = alloc(_gptr, units.length * sizeOf<Uint16>()).cast<Uint16>();
  // Three ULARGE_INTEGERs: free to the caller, total, free overall.
  final out = alloc(_gptr, 3 * sizeOf<Uint64>()).cast<Uint64>();
  try {
    if (name == nullptr || out == nullptr) return null;
    name.asTypedList(units.length).setAll(0, units);
    if (getSpace(name, out, out + 1, out + 2) == 0) return null;
    return (free: out[0], total: out[1]);
  } finally {
    if (name != nullptr) free(name.cast());
    if (out != nullptr) free(out.cast());
  }
}

/// GetDriveTypeW for [root] (a drive root such as `E:\`): one of the
/// `DRIVE_*` values, [driveRemovable] among them. 0 when it can't say.
int windowsDriveType(String root) {
  final alloc = _kernel32
      .lookupFunction<_LocalAllocNative, _LocalAllocDart>('LocalAlloc');
  final free =
      _kernel32.lookupFunction<_LocalFreeNative, _LocalFreeDart>('LocalFree');
  final getType = _kernel32.lookupFunction<_GetDriveTypeWNative,
      _GetDriveTypeWDart>('GetDriveTypeW');

  final units = utf16z(root);
  final name = alloc(_gptr, units.length * sizeOf<Uint16>()).cast<Uint16>();
  try {
    if (name == nullptr) return 0;
    name.asTypedList(units.length).setAll(0, units);
    return getType(name);
  } finally {
    if (name != nullptr) free(name.cast());
  }
}

/// Stop Windows from showing a dialog when a drive letter with no disk in
/// it (an empty card reader) is touched: the card scan looks at all 26.
/// Process-wide, so it is set once at startup, keeping any bits already set.
void suppressDriveErrorDialogs() {
  final setErrorMode = _kernel32
      .lookupFunction<_SetErrorModeNative, _SetErrorModeDart>('SetErrorMode');
  const wanted = _semFailCriticalErrors | _semNoOpenFileErrorBox;
  final previous = setErrorMode(wanted);
  setErrorMode(previous | wanted);
}
