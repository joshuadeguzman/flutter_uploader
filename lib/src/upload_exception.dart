part of flutter_uploader;

class UploadException extends Equatable implements Exception {
  final String taskId;
  final int statusCode;
  final UploadTaskStatus status;
  final String tag;
  final String message;
  final String code;

  UploadException({
    this.taskId,
    this.statusCode,
    this.status,
    this.tag,
    this.message,
    this.code,
  });

  @override
  bool get stringify => true;

  @override
  List<Object> get props {
    return [
      taskId,
      statusCode,
      status,
      tag,
      message,
      code,
    ];
  }
}
