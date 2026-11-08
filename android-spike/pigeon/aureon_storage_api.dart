import 'package:pigeon/pigeon.dart';

class TransferSnapshot {
  String? operationId;
  String? status;
  int? acknowledgedBytes;
  int? totalBytes;
  bool? remoteVerified;
}

@HostApi()
abstract class AureonStorageHostApi {
  @async
  TransferSnapshot? getTransfer(String operationId);

  @async
  List<TransferSnapshot> listTransfers();

  @async
  void pauseTransfer(String operationId);

  @async
  void resumeTransfer(String operationId);
}
