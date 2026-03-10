enum MediaType { video, images }

class VideoInfo {
  final String id;
  final String? title;
  final String downloadUrl;
  final MediaType mediaType;
  List<String> imageUrls;
  String? localPath;
  List<String> localImagePaths;

  VideoInfo({
    required this.id,
    this.title,
    required this.downloadUrl,
    this.mediaType = MediaType.video,
    this.imageUrls = const [],
    this.localPath,
    this.localImagePaths = const [],
  });
}

class ResolveRequest {
  final String text;
  final Map<String, Map<String, String>> cookies;

  ResolveRequest({required this.text, this.cookies = const {}});

  Map<String, dynamic> toJson() => {
        'text': text,
        'cookies': cookies,
      };
}

class ResolveResponse {
  final String? inputUrl;
  final String? webpageUrl;
  final String? title;
  final String? videoId;
  final String? downloadUrl;
  final String? mediaType;
  final List<String>? imageUrls;

  ResolveResponse({
    this.inputUrl,
    this.webpageUrl,
    this.title,
    this.videoId,
    this.downloadUrl,
    this.mediaType,
    this.imageUrls,
  });

  factory ResolveResponse.fromJson(Map<String, dynamic> json) {
    return ResolveResponse(
      inputUrl: json['input_url'] as String?,
      webpageUrl: json['webpage_url'] as String?,
      title: json['title'] as String?,
      videoId: json['video_id'] as String?,
      downloadUrl: json['download_url'] as String?,
      mediaType: json['media_type'] as String?,
      imageUrls: (json['image_urls'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
    );
  }
}
