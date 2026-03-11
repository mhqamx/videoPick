export enum MediaType {
  video = 'video',
  images = 'images',
}

export interface VideoInfo {
  id: string;
  title?: string;
  downloadUrl: string;
  mediaType: MediaType;
  imageUrls: string[];
  localPath?: string;
  localImagePaths: string[];
}

export interface ResolveRequest {
  text: string;
  cookies: Record<string, Record<string, string>>;
}

export interface ResolveResponse {
  input_url?: string;
  webpage_url?: string;
  title?: string;
  video_id?: string;
  download_url?: string;
  media_type?: string;
  image_urls?: string[];
}
