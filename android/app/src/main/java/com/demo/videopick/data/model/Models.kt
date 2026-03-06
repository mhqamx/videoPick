package com.demo.videopick.data.model

import kotlinx.serialization.Serializable

enum class MediaType { VIDEO, IMAGES }

data class VideoInfo(
    val id: String,
    val downloadUrl: String,
    val localPath: String? = null,
    val title: String? = null,
    val mediaType: MediaType = MediaType.VIDEO,
    val imageUrls: List<String> = emptyList(),
    val localImagePaths: List<String> = emptyList(),
)

// Backend API models
@Serializable
data class ResolveRequest(
    val text: String,
    val cookies: Map<String, Map<String, String>>? = null,
)

@Serializable
data class ResolveResponse(
    val input_url: String,
    val webpage_url: String? = null,
    val title: String? = null,
    val video_id: String? = null,
    val download_url: String,
    val media_type: String = "video",
    val image_urls: List<String> = emptyList(),
)

@Serializable
data class ErrorResponse(
    val detail: String,
)
