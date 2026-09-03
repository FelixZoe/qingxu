import 'dart:io';

import 'package:binary_patch/binary_patch.dart';
import 'package:crypto/crypto.dart';

Future<Digest> _digest(String path) => sha256.bind(File(path).openRead()).first;

Future<void> main(List<String> arguments) async {
  if (arguments.length != 3) {
    stderr.writeln(
      'Usage: dart run tool/create_binary_patch.dart <old> <new> <patch>',
    );
    exitCode = 64;
    return;
  }

  final oldPath = arguments[0];
  final newPath = arguments[1];
  final patchPath = arguments[2];
  final verificationPath = '$patchPath.verified';

  for (final path in [oldPath, newPath]) {
    if (!File(path).existsSync()) {
      stderr.writeln('Input file does not exist: $path');
      exitCode = 66;
      return;
    }
  }

  try {
    final result = await BinaryPatch.create(
      oldFile: oldPath,
      newFile: newPath,
      outputPatch: patchPath,
      options: PatchOptions.fast(),
    );
    stdout.writeln(result.summary);

    await BinaryPatch.apply(
      oldFile: oldPath,
      patchFile: patchPath,
      outputFile: verificationPath,
    );

    final expected = await _digest(newPath);
    final actual = await _digest(verificationPath);
    if (expected.toString() != actual.toString()) {
      stderr.writeln('Patch round-trip verification failed.');
      exitCode = 1;
      return;
    }
    stdout.writeln('Patch round-trip verified: $actual');
  } finally {
    final verification = File(verificationPath);
    if (verification.existsSync()) {
      verification.deleteSync();
    }
  }
}
