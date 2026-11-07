import 'package:pigeon/pigeon.dart';

class TransferSnapshot {
  String operationId = '';
  String status = '';
  int acknowledgedBytes = 0;
  int? totalBytes;
  bool remoteVerified = false;
}

@HostApi()
abstract class AureonStorageHostApi {
  @async
  TransferSnapshot? getTransfer(String operationId);

  @async
  void pauseTransfer(String operationId);

  @async
  void resumeTransfer(String operationId);
}
